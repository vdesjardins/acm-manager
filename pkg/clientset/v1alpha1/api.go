package v1alpha1

import (
	"k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	api "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"
)

type Interface interface {
	Certificates(namespace string) CertificateInterface
}

type Client struct {
	restClient rest.Interface
}

func NewForConfig(c *rest.Config) (*Client, error) {
	err := AddToScheme(scheme.Scheme)
	if err != nil {
		return nil, err
	}

	config := *c
	config.ContentConfig.GroupVersion = &api.SchemeGroupVersion
	config.APIPath = "/apis"
	config.NegotiatedSerializer = scheme.Codecs.WithoutConversion()
	config.UserAgent = rest.DefaultKubernetesUserAgent()

	client, err := rest.RESTClientFor(&config)
	if err != nil {
		return nil, err
	}

	return &Client{restClient: client}, nil
}

func (c *Client) Certificates(namespace string) CertificateInterface {
	return &certificateClient{
		restClient: c.restClient,
		ns:         namespace,
	}
}
