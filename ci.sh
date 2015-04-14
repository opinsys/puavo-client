
#!/bin/sh

set -eu
set -x


# Install build dependencies
sudo make install-build-dep

# Build debian package
make deb

cp ../puavo-client_* $HOME/results
