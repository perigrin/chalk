# ABOUTME: %SIG's metaobject: the handler table warn and die ask (__WARN__, __DIE__), answering
# ABOUTME: the container protocol; compiled into a program by chalk (Chalk::Impl), not a tie.
use 5.42.0;
use utf8;

package Chalk::Impl::SIG;

# A handler is stored and fetched by its name; a signal's is kept like any
# value (a signal being raised is not chalk's: kill and alarm are refused).
# Which signals the system has is the system's: a question that needs that
# list stops the program by name.

sub new ($class) { return bless {}, $class }

sub FETCH ($self, $key) { return $self->{$key} }

sub STORE ($self, $key, $value) { $self->{$key} = $value; return }

# perl's %SIG holds every signal's name from the start; __WARN__ and __DIE__
# only once set.
sub EXISTS ($self, $key) {
    return 1 if exists $self->{$key};
    return '' if $key eq '__WARN__' || $key eq '__DIE__';
    return refuse("an exists of the signal $key in %SIG (which signals there are is the system's)");
}

sub DELETE ($self, $key) { return delete $self->{$key} }

sub CLEAR ($self) { return refuse('%SIG emptied or assigned whole') }

sub FIRSTKEY ($self) { return refuse("the keys of %SIG (which signals there are is the system's)") }

sub NEXTKEY ($self, $last) { return refuse("the keys of %SIG (which signals there are is the system's)") }

# refuse($why): a question chalk does not answer, stopped by name at run time.
sub refuse ($why) {
    print STDERR "chalk: refused at run time: $why\n";
    exit 255;
}

1;
