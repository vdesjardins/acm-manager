module vdesjardins/acm-manager

go 1.16

require (
	github.com/aws/aws-sdk-go-v2 v1.17.4
	github.com/aws/aws-sdk-go-v2/config v1.18.12
	github.com/aws/aws-sdk-go-v2/service/acm v1.9.2
	github.com/evanphx/json-patch v5.6.0+incompatible // indirect
	github.com/hashicorp/go-multierror v1.1.1
	github.com/onsi/ginkgo v1.16.5
	github.com/onsi/gomega v1.17.0
	k8s.io/api v0.23.3
	k8s.io/apimachinery v0.23.3
	k8s.io/client-go v0.23.1
	sigs.k8s.io/controller-runtime v0.11.0
	sigs.k8s.io/external-dns v0.12.0
)
