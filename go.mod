module vdesjardins/acm-manager

go 1.16

require (
	github.com/aws/aws-sdk-go-v2 v1.16.7
	github.com/aws/aws-sdk-go-v2/config v1.11.0
	github.com/aws/aws-sdk-go-v2/service/acm v1.9.2
	github.com/hashicorp/go-multierror v1.1.1
	github.com/onsi/ginkgo v1.16.5
	github.com/onsi/gomega v1.16.0
	k8s.io/api v0.25.0-alpha.2
	k8s.io/apimachinery v0.25.0-alpha.2
	k8s.io/client-go v0.23.0-alpha.3
	sigs.k8s.io/controller-runtime v0.11.0-beta.0
	sigs.k8s.io/external-dns v0.10.1
)
