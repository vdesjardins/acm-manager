package v1alpha1

import (
	"context"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"k8s.io/apimachinery/pkg/watch"
	"k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"vdesjardins/acm-manager/pkg/api/v1alpha1"
)

var (
	certificates = "certificates"
)

//CertificateInterface is a interface for interacting with a Certificate
type CertificateInterface interface {
	Get(ctx context.Context, name string, opts metav1.GetOptions) (*v1alpha1.Certificate, error)
	Create(ctx context.Context, cert *v1alpha1.Certificate, opts metav1.CreateOptions) (*v1alpha1.Certificate, error)
	Update(ctx context.Context, cert *v1alpha1.Certificate, opts metav1.UpdateOptions) (*v1alpha1.Certificate, error)
	Delete(ctx context.Context, name string, opts metav1.DeleteOptions) error
	Watch(ctx context.Context, opts metav1.ListOptions) (watch.Interface, error)
}

type certificateClient struct {
	restClient rest.Interface
	ns         string
}

func (c *certificateClient) Get(ctx context.Context, name string, opts metav1.GetOptions) (*v1alpha1.Certificate, error) {
	result := v1alpha1.Certificate{}
	err := c.restClient.Get().
		Namespace(c.ns).
		Resource(certificates).
		VersionedParams(&opts, scheme.ParameterCodec).
		Name(name).
		Do(ctx).
		Into(&result)

	return &result, err
}

func (c *certificateClient) Create(ctx context.Context, cert *v1alpha1.Certificate, opts metav1.CreateOptions) (*v1alpha1.Certificate, error) {
	result := v1alpha1.Certificate{}
	err := c.restClient.Post().
		Namespace(c.ns).
		Resource(certificates).
		VersionedParams(&opts, scheme.ParameterCodec).
		Body(cert).
		Do(ctx).
		Into(&result)

	return &result, err
}

func (c *certificateClient) Update(ctx context.Context, cert *v1alpha1.Certificate, opts metav1.UpdateOptions) (*v1alpha1.Certificate, error) {
	result := v1alpha1.Certificate{}
	err := c.restClient.Put().
		Namespace(c.ns).
		Resource(certificates).
		Name(cert.Name).
		VersionedParams(&opts, scheme.ParameterCodec).
		Body(cert).
		Do(ctx).
		Into(&result)

	return &result, err
}

func (c *certificateClient) Delete(ctx context.Context, name string, opts metav1.DeleteOptions) error {
	return c.restClient.Delete().
		Namespace(c.ns).
		Resource(certificates).
		VersionedParams(&opts, scheme.ParameterCodec).
		Name(name).
		Do(ctx).
		Error()
}

func (c *certificateClient) Watch(ctx context.Context, opts metav1.ListOptions) (watch.Interface, error) {
	var timeout time.Duration
	if opts.TimeoutSeconds != nil {
		timeout = time.Duration(*opts.TimeoutSeconds) * time.Second
	}
	opts.Watch = true
	return c.restClient.Get().
		Resource(certificates).
		VersionedParams(&opts, scheme.ParameterCodec).
		Timeout(timeout).
		Watch(ctx)
}
