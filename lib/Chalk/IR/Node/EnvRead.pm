# ABOUTME: EnvRead node — reads a %ENV entry via the host C interface (getenv).
# ABOUTME: Host process state, not libperl; key is a compile-time-known string.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::EnvRead :isa(Chalk::IR::Node) {
    # Environment variable name (compile-time literal). Env writes are not
    # modelled, so the read is constant per process and hash-consing two
    # reads of the same key to one node is sound.
    field $key :param :reader;

    method operation() { 'EnvRead' }

    method content_hash() {
        return join('|', 'EnvRead', "key=$key", $self->_serialize_inputs());
    }
}
