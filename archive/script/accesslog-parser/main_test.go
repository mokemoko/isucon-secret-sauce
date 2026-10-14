package main

import "testing"

func BenchmarkLoadLog(b *testing.B) {
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = loadLog()
	}
}

func BenchmarkConvertData(b *testing.B) {
	data := loadLog()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = convertData(data)
	}
}

func BenchmarkExportJSON(b *testing.B) {
	data := convertData(loadLog())
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		exportJSON(data)
	}
}
