/*
Copyright 2017 Frederic Branczyk All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package authn

import (
	"context"
	"os"

	"k8s.io/apiserver/pkg/apis/apiserver"
	"k8s.io/apiserver/pkg/authentication/authenticator"
	"k8s.io/apiserver/pkg/authentication/request/bearertoken"
	"k8s.io/apiserver/pkg/server/dynamiccertificates"
	"k8s.io/apiserver/plugin/pkg/authenticator/token/oidc"
)

// OIDCConfig represents configuration used for JWT request authentication
type OIDCConfig struct {
	IssuerURL            string
	ClientID             string
	CAFile               string
	UsernameClaim        string
	UsernamePrefix       string
	GroupsClaim          string
	GroupsPrefix         string
	SupportedSigningAlgs []string
}

// NewOIDCAuthenticator returns OIDC authenticator
func NewOIDCAuthenticator(config *OIDCConfig) (authenticator.Request, error) {
	opts := oidc.Options{
		JWTAuthenticator: apiserver.JWTAuthenticator{
			Issuer: apiserver.Issuer{
				URL:       config.IssuerURL,
				Audiences: []string{config.ClientID},
			},
			ClaimMappings: apiserver.ClaimMappings{
				Username: apiserver.PrefixedClaimOrExpression{
					Claim:  config.UsernameClaim,
					Prefix: &config.UsernamePrefix,
				},
				Groups: apiserver.PrefixedClaimOrExpression{
					Claim:  config.GroupsClaim,
					Prefix: &config.GroupsPrefix,
				},
			},
		},
		SupportedSigningAlgs: config.SupportedSigningAlgs,
	}

	if config.CAFile != "" {
		caBundle, err := os.ReadFile(config.CAFile)
		if err != nil {
			return nil, err
		}
		caProvider, err := dynamiccertificates.NewStaticCAContent("oidc-ca", caBundle)
		if err != nil {
			return nil, err
		}
		opts.CAContentProvider = caProvider
	}

	tokenAuthenticator, err := oidc.New(context.Background(), opts)
	if err != nil {
		return nil, err
	}

	return bearertoken.New(tokenAuthenticator), nil
}
