package main

import (
	"bufio"
	"encoding/json"
	"github.com/Songmu/go-ltsv"
	"io"
	"io/ioutil"
	"log"
	"os"
	"sort"
)

type AccessLog struct {
	Msec    float64
	Req     string
	Status  int
	Size    int
	UA      string
	ReqTime float64
	Cookie  string
}

type ExportData struct {
	Key  string      `json:"key"`
	Data []ExportRow `json:"data"`
}

type ExportRow struct {
	Path  string `json:"path"`
	Start int    `json:"start"`
	End   int    `json:"end"`
}

func loadLog() []AccessLog {
	var res []AccessLog
	f, err := os.Open("access.log")
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()

	br := bufio.NewReader(f)

	for {
		line, _, err := br.ReadLine()
		if err == io.EOF {
			break
		}
		if err != nil {
			log.Fatal(err)
		}
		l := &AccessLog{}
		err = ltsv.Unmarshal(line, l)
		if err != nil {
			log.Fatal(err)
		}
		res = append(res, *l)
	}

	return res
}

func convertData(data []AccessLog) []ExportData {
	tmp := map[string]*ExportData{}
	initTime := int((data[0].Msec - data[0].ReqTime) * 1000)
	for _, l := range data {
		if _, ok := tmp[l.Cookie]; !ok {
			tmp[l.Cookie] = &ExportData{
				Key: l.Cookie,
			}
		}
		tmp[l.Cookie].Data = append(tmp[l.Cookie].Data, ExportRow{
			Path:  l.Req,
			Start: int((l.Msec-l.ReqTime)*1000) - initTime,
			End:   int(l.Msec*1000) - initTime,
		})
	}
	var res []ExportData
	for _, v := range tmp {
		res = append(res, *v)
	}
	sort.Slice(res, func(i, j int) bool {
		return res[i].Data[0].Start < res[j].Data[0].Start
	})
	return res
}

func exportJSON(data []ExportData) {
	b, err := json.Marshal(data)
	if err != nil {
		log.Fatal(err)
	}
	err = ioutil.WriteFile("out.json", b, os.ModePerm)
	if err != nil {
		log.Fatal(err)
	}
}

func main() {
	data := loadLog()
	converted := convertData(data)
	exportJSON(converted)
}
