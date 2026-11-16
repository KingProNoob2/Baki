// baki-notify is a small self-hosted push server for the Baki app. The app registers its device
// token plus the user's Bakaláři login; the server then polls Bakaláři every couple of minutes and
// sends an Apple push for new marks, Komens messages, noticeboard posts and timetable changes.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

type Config struct {
	Listen      string     `json:"listen"`       // default :8787 (put a TLS reverse proxy in front)
	APIKey      string     `json:"api_key"`      // shared secret the app sends when registering
	PollSeconds int        `json:"poll_seconds"` // default 120
	DataDir     string     `json:"data_dir"`     // default ./data
	APNs        APNsConfig `json:"apns"`
}

func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	if cfg.Listen == "" {
		cfg.Listen = ":8787"
	}
	if cfg.PollSeconds <= 0 {
		cfg.PollSeconds = 120
	}
	if cfg.DataDir == "" {
		cfg.DataDir = "data"
	}
	if len(cfg.APIKey) < 16 {
		return nil, fmt.Errorf("api_key is required and must be at least 16 characters")
	}
	a := cfg.APNs
	if a.KeyFile == "" || a.KeyID == "" || a.TeamID == "" || a.BundleID == "" {
		return nil, fmt.Errorf("apns.key_file, key_id, team_id and bundle_id are required")
	}
	return &cfg, nil
}

func main() {
	path := "config.json"
	if len(os.Args) > 1 {
		path = os.Args[1]
	} else if env := os.Getenv("BAKI_NOTIFY_CONFIG"); env != "" {
		path = env
	}
	cfg, err := loadConfig(path)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	if err := os.MkdirAll(cfg.DataDir, 0o700); err != nil {
		log.Fatalf("data dir: %v", err)
	}
	apns, err := NewAPNs(cfg.APNs)
	if err != nil {
		log.Fatalf("apns: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	mgr := NewManager(ctx, cfg, apns)
	mgr.Start()

	srv := &http.Server{Addr: cfg.Listen, Handler: newAPI(cfg, mgr), ReadHeaderTimeout: 10 * time.Second}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdown)
	}()
	log.Printf("listening on %s, polling every %ds", cfg.Listen, cfg.PollSeconds)
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatal(err)
	}
	mgr.Wait()
}
