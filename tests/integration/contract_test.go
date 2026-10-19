package integration

import (
	"net/http"
	"os"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"go.yaml.in/yaml/v3"
)

var paramRe = regexp.MustCompile(`\{[^}]+\}`)

// TestOpenAPIMatchesRouter fails when a route exists without documentation or vice versa.
func TestOpenAPIMatchesRouter(t *testing.T) {
	raw, err := os.ReadFile("../../docs/openapi.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var spec struct {
		Paths map[string]map[string]any `yaml:"paths"`
	}
	if err := yaml.Unmarshal(raw, &spec); err != nil {
		t.Fatal(err)
	}
	documented := map[string]bool{}
	for p, ops := range spec.Paths {
		for m := range ops {
			documented[strings.ToUpper(m)+" "+paramRe.ReplaceAllString(p, "{}")] = true
		}
	}
	routed := map[string]bool{}
	err = chi.Walk(app.Router().(chi.Routes), func(method, route string, _ http.Handler, _ ...func(http.Handler) http.Handler) error {
		if !strings.HasPrefix(route, "/api/v1/") {
			return nil
		}
		route = strings.TrimSuffix(strings.TrimPrefix(route, "/api/v1"), "/")
		routed[method+" "+paramRe.ReplaceAllString(route, "{}")] = true
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	var missingDoc, missingRoute []string
	for r := range routed {
		if !documented[r] {
			missingDoc = append(missingDoc, r)
		}
	}
	for d := range documented {
		if !routed[d] {
			missingRoute = append(missingRoute, d)
		}
	}
	sort.Strings(missingDoc)
	sort.Strings(missingRoute)
	if len(missingDoc) > 0 || len(missingRoute) > 0 {
		t.Fatalf("contract drift\n  routed but undocumented: %v\n  documented but not routed: %v", missingDoc, missingRoute)
	}
}
