package external_api_clients

import (
	"context"
	apiV1 "vdesjardins/acm-manager/pkg/apis/acmmanager/v1alpha1"
	"vdesjardins/acm-manager/pkg/clientset/v1alpha1"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

type certificateRestClient struct {
	client *v1alpha1.Client
}

type CertificateRestAPI interface {
	GetCertificateForNamespace(ctx context.Context, namespace string, certificateName string, options metav1.GetOptions) (*apiV1.Certificate, error)
}

var NewCertificateRestClient = func(ctx context.Context) (CertificateRestAPI, error) {

	log := log.FromContext(ctx).WithName("certificate rest client")

	clientConfig, err := ctrl.GetConfig()
	if err != nil {
		log.Error(err, "unable to read kube config")
		return nil, err
	}
	certClient, err := v1alpha1.NewForConfig(clientConfig)
	if err != nil {
		log.Error(err, "unable to create certificate client")
		return nil, err
	}

	return &certificateRestClient{client: certClient}, nil
}

func (certRestClient *certificateRestClient) GetCertificateForNamespace(ctx context.Context, namespace string, certificateName string, options metav1.GetOptions) (*apiV1.Certificate, error) {
	return certRestClient.client.Certificates(namespace).Get(ctx, certificateName, metav1.GetOptions{})
}
