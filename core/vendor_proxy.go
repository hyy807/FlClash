package core

import (
	"bytes"

	"github.com/metacubex/mihomo/log"
	"go.yaml.in/yaml/v3"
)

// The vendor's x365 type is VLESS with REALITY over HTTP/2 carrying its fields
// under private names. mihomo already dials that shape, so an imported profile
// is translated in place rather than growing a new outbound: the vendor gets no
// special path in the tunnel, and its nodes keep every upstream feature.
const vendorRealityProxyType = "x365"

func hasVendorProxies(buf []byte) bool {
	return bytes.Contains(buf, []byte(vendorRealityProxyType))
}

// rewriteVendorProxies is safe on any document: it reports how many nodes it
// translated, so a caller can tell an untouched profile from a rewritten one.
func rewriteVendorProxies(document *yaml.Node) int {
	root := documentRoot(document)
	if root == nil {
		return 0
	}
	proxies := mappingValue(root, "proxies")
	if proxies == nil {
		return 0
	}
	proxies = resolveAlias(proxies)
	if proxies.Kind != yaml.SequenceNode {
		return 0
	}
	rewritten := 0
	for _, item := range proxies.Content {
		item = resolveAlias(item)
		if item.Kind != yaml.MappingNode {
			continue
		}
		if scalarValue(item, "type") != vendorRealityProxyType {
			continue
		}
		if rewriteVendorProxy(item) {
			rewritten++
		}
	}
	return rewritten
}

// rewriteVendorProxy needs the REALITY public key, the one field with no mihomo
// equivalent to fall back on, so a node missing it stays untouched and fails
// loudly at parse time instead of silently dialling the wrong thing.
func rewriteVendorProxy(proxy *yaml.Node) bool {
	publicKey := scalarValue(proxy, "public-key")
	if publicKey == "" {
		log.Warnln("x365 proxy %q has no public-key, left unchanged", scalarValue(proxy, "name"))
		return false
	}
	host := scalarValue(proxy, "host")
	serverName := scalarValue(proxy, "servername")
	if serverName == "" {
		serverName = host
	}
	path := scalarValue(proxy, "path")
	if path == "" {
		path = "/"
	}

	setScalarValue(proxy, "type", "!!str", "vless")
	setScalarValue(proxy, "tls", "!!bool", "true")
	setScalarValue(proxy, "network", "!!str", "h2")
	if serverName != "" {
		setScalarValue(proxy, "servername", "!!str", serverName)
	}
	if scalarValue(proxy, "client-fingerprint") == "" {
		setScalarValue(proxy, "client-fingerprint", "!!str", "chrome")
	}

	reality := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
	appendScalarValue(reality, "public-key", publicKey)
	if shortID := scalarValue(proxy, "short-id"); shortID != "" {
		appendScalarValue(reality, "short-id", shortID)
	}
	setMappingValue(proxy, "reality-opts", reality)

	h2 := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
	if host != "" {
		hosts := &yaml.Node{
			Kind:    yaml.SequenceNode,
			Tag:     "!!seq",
			Content: []*yaml.Node{{Kind: yaml.ScalarNode, Tag: "!!str", Value: host}},
		}
		setMappingValue(h2, "host", hosts)
	}
	appendScalarValue(h2, "path", path)
	setMappingValue(proxy, "h2-opts", h2)

	for _, key := range []string{"public-key", "short-id", "host", "path"} {
		removeMappingValue(proxy, key)
	}
	return true
}

func documentRoot(document *yaml.Node) *yaml.Node {
	node := document
	for node != nil {
		switch node.Kind {
		case yaml.DocumentNode:
			if len(node.Content) == 0 {
				return nil
			}
			node = node.Content[0]
		case yaml.AliasNode:
			node = node.Alias
		default:
			return node
		}
	}
	return nil
}

func scalarValue(mapping *yaml.Node, key string) string {
	value := mappingValue(mapping, key)
	if value == nil {
		return ""
	}
	value = resolveAlias(value)
	if value.Kind != yaml.ScalarNode {
		return ""
	}
	return value.Value
}

func setScalarValue(mapping *yaml.Node, key, tag, value string) {
	setMappingValue(mapping, key, &yaml.Node{Kind: yaml.ScalarNode, Tag: tag, Value: value})
}

func appendScalarValue(mapping *yaml.Node, key, value string) {
	mapping.Content = append(
		mapping.Content,
		&yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: key},
		&yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: value},
	)
}

func removeMappingValue(mapping *yaml.Node, key string) {
	for i := 0; i+1 < len(mapping.Content); i += 2 {
		name := mapping.Content[i]
		if name.Kind == yaml.ScalarNode && name.Value == key {
			mapping.Content = append(mapping.Content[:i], mapping.Content[i+2:]...)
			return
		}
	}
}
