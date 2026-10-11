//go:build dsembed

package assets

import _ "embed"

var (
	//go:embed embedded/build.json
	buildJSON []byte
	//go:embed embedded/assets.tar.gz
	archiveData []byte
)
