// ISUCON 自律チューニングのダッシュボード。
// state/ (bench.jsonl, analysis/, phase) と Orca orchestration の状態を読み、人間の示唆・ゲート回答を Orca に流す。
// 問題情報を外に出さないため、必ず 127.0.0.1 か Tailscale のアドレスで待ち受けること。
// 起動: cd dashboard && go run . [-run <run_id>] [-end 2026-10-31T18:00:00+09:00] [-addr <tailscale-ip>:9180]  (省略時は state/run_id・state/end)
package main

import (
	"bufio"
	"context"
	_ "embed"
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

//go:embed index.html
var indexHTML []byte

//go:embed bench.html
var benchHTML []byte

var (
	addr     = flag.String("addr", "127.0.0.1:9180", "listen address (localhost か Tailscale IP のみ。8080 等は競技アプリと衝突しやすいので避ける)")
	stateDir = flag.String("state", "../state", "bench lane の state ディレクトリ")
	runID    = flag.String("run", "", "Orca orchestration Run id。省略時は <state>/run_id")
	endAt    = flag.String("end", "", "競技終了時刻 RFC3339 (例 2026-10-31T18:00:00+09:00)。省略時は <state>/end")
	orcaBin  = flag.String("orca", "orca", "orca CLI")
)

func orca(args ...string) (json.RawMessage, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, *orcaBin, append(args, "--json")...).Output()
	if err != nil {
		return nil, err
	}
	var env struct {
		Result json.RawMessage `json:"result"`
	}
	if err := json.Unmarshal(out, &env); err != nil {
		return nil, err
	}
	return env.Result, nil
}

func readBench() []json.RawMessage {
	rows := []json.RawMessage{}
	f, err := os.Open(filepath.Join(*stateDir, "bench.jsonl"))
	if err != nil {
		return rows
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(nil, 1<<20)
	for sc.Scan() {
		if json.Valid(sc.Bytes()) {
			rows = append(rows, append(json.RawMessage{}, sc.Bytes()...))
		}
	}
	return rows
}

// ponytail: リクエスト毎に orca CLI を叩く。閲覧者3人×3秒ポーリングなら十分、重ければ数秒キャッシュを足す
func handleState(w http.ResponseWriter, r *http.Request) {
	end := *endAt
	if end == "" {
		b, _ := os.ReadFile(filepath.Join(*stateDir, "end"))
		end = strings.TrimSpace(string(b))
	}
	res := map[string]any{"run": *runID, "end": end, "errors": []string{}}
	errs := []string{}
	phase, _ := os.ReadFile(filepath.Join(*stateDir, "phase"))
	res["phase"] = strings.TrimSpace(string(phase))
	bench := readBench()
	res["bench"] = bench

	if len(bench) > 0 {
		var last struct{ ID string }
		json.Unmarshal(bench[len(bench)-1], &last)
		res["analysis"] = map[string]any{"id": last.ID}
	}

	for key, args := range map[string][]string{
		"tasks": {"orchestration", "task-list", "--run", *runID},
		"gates": {"orchestration", "gate-list", "--run", *runID, "--status", "pending"},
	} {
		raw, err := orca(args...)
		if err != nil {
			errs = append(errs, key+": "+err.Error())
			continue
		}
		var m map[string]json.RawMessage
		json.Unmarshal(raw, &m)
		res[key] = m[key]
	}
	res["errors"] = errs
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(res)
}

var benchID = regexp.MustCompile(`^[0-9]{6}-[0-9a-f]{7}$`)

// handleBench は1ベンチ分の台帳行・前後のベンチ・ホスト別ファイル一覧を返す。中身の JSON は /state/ から直接読ませる
func handleBench(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if !benchID.MatchString(id) { // パストラバーサル防止も兼ねる
		http.Error(w, "bad id", http.StatusBadRequest)
		return
	}
	rows := readBench()
	res := map[string]any{"id": id}
	for i, raw := range rows {
		var row struct{ ID string }
		json.Unmarshal(raw, &row)
		if row.ID != id {
			continue
		}
		res["row"] = raw
		if i > 0 {
			res["prev"] = rows[i-1]
		}
		if i+1 < len(rows) {
			res["next"] = rows[i+1]
		}
	}
	hosts := map[string][]string{}
	dirs, _ := os.ReadDir(filepath.Join(*stateDir, "analysis", id))
	for _, d := range dirs {
		if !d.IsDir() {
			continue
		}
		files, _ := os.ReadDir(filepath.Join(*stateDir, "analysis", id, d.Name()))
		names := []string{}
		for _, f := range files {
			names = append(names, f.Name())
		}
		hosts[d.Name()] = names
	}
	res["hosts"] = hosts
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(res)
}

// post は JSON 限定にして、他サイトからのフォーム POST (CSRF) を CORS プリフライトで弾く
func post(fn func(body map[string]string) ([]string, error)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.Header.Get("Content-Type") != "application/json" {
			http.Error(w, "POST application/json only", http.StatusBadRequest)
			return
		}
		var body map[string]string
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		args, err := fn(body)
		if err == nil {
			_, err = orca(args...)
		}
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func main() {
	flag.Parse()
	if *runID == "" {
		b, err := os.ReadFile(filepath.Join(*stateDir, "run_id"))
		if err != nil {
			log.Fatal("-run を指定するか、Coordinator の起動後に実行すること: ", err)
		}
		*runID = strings.TrimSpace(string(b))
	}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(indexHTML)
	})
	http.HandleFunc("/api/state", handleState)
	http.HandleFunc("/api/bench", handleBench)
	http.HandleFunc("/bench/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Write(benchHTML)
	})
	// 人間の示唆は status/high として Coordinator の Run inbox に入れる。escalation は Dispatch 外から送れないため。
	// Coordinator は check --wait --types に status を含めること
	http.HandleFunc("/api/hint", post(func(b map[string]string) ([]string, error) {
		text := strings.TrimSpace(b["text"])
		if text == "" {
			return nil, errBad("text が必要です")
		}
		return []string{"orchestration", "send", "--to", "run:" + *runID, "--type", "status", "--priority", "high",
			"--subject", "[human] " + b["who"], "--body", text}, nil
	}))
	// gate-resolve は呼び出し元の Run に束縛されていて外部プロセスからは実行できないため、
	// 回答をメッセージで送り、Coordinator 自身に gate-resolve させる
	http.HandleFunc("/api/gate", post(func(b map[string]string) ([]string, error) {
		if b["id"] == "" || b["resolution"] == "" {
			return nil, errBad("id と resolution が必要です")
		}
		return []string{"orchestration", "send", "--to", "run:" + *runID, "--type", "status", "--priority", "high",
			"--subject", "[human-gate] " + b["id"], "--body", b["resolution"]}, nil
	}))
	http.Handle("/state/", http.StripPrefix("/state/", http.FileServer(http.Dir(*stateDir))))
	log.Printf("dashboard on http://%s (run=%q state=%s)", *addr, *runID, *stateDir)
	log.Fatal(http.ListenAndServe(*addr, nil))
}

type errBad string

func (e errBad) Error() string { return string(e) }
