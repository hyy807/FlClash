package core

import (
	"os"
	"path/filepath"
	"testing"
)

const vendorProfile = `proxies:
  - name: ru81
    type: x365
    server: bgp01.example.com
    port: 443
    uuid: fe586856-88b5-43e3-951b-e8ff0aa51c29
    public-key: j-nB37c22JoYowzSbRtceenR6nq9JoseOPgWOHf11zo
    short-id: c7cb949d076c9e93
    servername: dldir1.qq.com
    host: dldir1.qq.com
    path: /ru81
    udp: false
  - name: plain
    type: socks5
    server: 127.0.0.1
    port: 1080
`

func TestHandleGetConfigRewritesVendorProxiesToVless(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte(vendorProfile), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}

	raw, err := handleGetConfig(path)
	if err != nil {
		t.Fatalf("handleGetConfig = %v", err)
	}
	if len(raw.Proxy) != 2 {
		t.Fatalf("proxies = %d, want 2", len(raw.Proxy))
	}

	proxy := raw.Proxy[0]
	if got := proxy["type"]; got != "vless" {
		t.Errorf("type = %#v, want vless", got)
	}
	if got := proxy["tls"]; got != true {
		t.Errorf("tls = %#v, want true", got)
	}
	if got := proxy["network"]; got != "h2" {
		t.Errorf("network = %#v, want h2", got)
	}
	if got := proxy["servername"]; got != "dldir1.qq.com" {
		t.Errorf("servername = %#v, want dldir1.qq.com", got)
	}
	if got := proxy["client-fingerprint"]; got != "chrome" {
		t.Errorf("client-fingerprint = %#v, want chrome", got)
	}
	if got := proxy["uuid"]; got != "fe586856-88b5-43e3-951b-e8ff0aa51c29" {
		t.Errorf("uuid = %#v, want the vendor uuid", got)
	}
	if got := proxy["udp"]; got != false {
		t.Errorf("udp = %#v, want false", got)
	}

	reality, _ := proxy["reality-opts"].(map[string]any)
	if reality["public-key"] != "j-nB37c22JoYowzSbRtceenR6nq9JoseOPgWOHf11zo" {
		t.Errorf("public-key = %#v, want the vendor key", reality["public-key"])
	}
	if reality["short-id"] != "c7cb949d076c9e93" {
		t.Errorf("short-id = %#v, want the vendor id", reality["short-id"])
	}

	h2, _ := proxy["h2-opts"].(map[string]any)
	if h2["path"] != "/ru81" {
		t.Errorf("h2 path = %#v, want /ru81", h2["path"])
	}
	hosts, _ := h2["host"].([]any)
	if len(hosts) != 1 || hosts[0] != "dldir1.qq.com" {
		t.Errorf("h2 host = %#v, want [dldir1.qq.com]", h2["host"])
	}

	for _, key := range []string{"public-key", "short-id", "host", "path"} {
		if _, ok := proxy[key]; ok {
			t.Errorf("vendor key %q survived the rewrite", key)
		}
	}

	if got := raw.Proxy[1]["type"]; got != "socks5" {
		t.Errorf("socks5 proxy type = %#v, want it untouched", got)
	}
}

func TestHandleGetConfigKeepsAVendorProxyWithoutAPublicKey(t *testing.T) {
	profile := `proxies:
  - name: broken
    type: x365
    server: bgp01.example.com
    port: 443
    uuid: fe586856-88b5-43e3-951b-e8ff0aa51c29
`
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte(profile), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}

	raw, err := handleGetConfig(path)
	if err != nil {
		t.Fatalf("handleGetConfig = %v", err)
	}
	if got := raw.Proxy[0]["type"]; got != vendorRealityProxyType {
		t.Errorf("type = %#v, want it left as %s", got, vendorRealityProxyType)
	}
}

func TestHandleGetConfigLeavesProfilesWithoutVendorProxiesToMihomo(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte("mixed-port: 7899\n"), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}

	raw, err := handleGetConfig(path)
	if err != nil {
		t.Fatalf("handleGetConfig = %v", err)
	}
	if raw.MixedPort != 7899 {
		t.Errorf("mixed-port = %d, want 7899", raw.MixedPort)
	}
}
