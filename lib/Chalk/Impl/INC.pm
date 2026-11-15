# ABOUTME: %INC's metaobject: the module registry -- the modules the program loaded as chalk saw it
# ABOUTME: compile, and each built-in a require enters -- answering exists and truth, nothing more.
use 5.42.0;
use utf8;

package Chalk::Impl::INC;

# A key's VALUE is a path, perl's file system's, not chalk's: T2 lets a
# program read one only as a truth (the builder refuses any other use), so
# FETCH answers 1 for a module loaded. A key the registry does not hold may
# still be loaded (by a module chalk did not follow): that question stops
# the program by name rather than answer "no" wrongly. A store or a delete
# fakes a load: stopped by name.

# new($class, $whole, @loaded): $whole where the registry is all perl's %INC
# can hold (the program loads only modules that load no other): a key not
# in it is no module loaded. (There is one registry: whole is the class's.)
sub new ($class, $whole, @loaded) {
    my $self = bless {}, $class;
    $Chalk::Impl::INC::WHOLE = $whole;
    for my $key (@loaded) { $self->{$key} = 1 }
    return $self;
}

# enter($key): a require of a built-in module (strict, warnings) loads no
# file and enters it here.
sub enter ($self, $key) { $self->{$key} = 1; return 1 }

sub EXISTS ($self, $key) {
    return 1 if exists $self->{$key};
    return '' if $Chalk::Impl::INC::WHOLE;
    return refuse("whether $key is in %INC (a module chalk did not see loaded may be)");
}

# (EXISTS called as the sub it is, not as a method: a method call by name
# may reach every loaded module's EXISTS, and with it their code)
sub FETCH ($self, $key) { return EXISTS( $self, $key ) ? 1 : undef }

sub STORE ($self, $key, $value) { return refuse("a store into %INC (of $key: a load faked)") }

sub DELETE ($self, $key) { return refuse("a delete from %INC (of $key: a load undone)") }

sub CLEAR ($self) { return refuse('%INC emptied or assigned whole') }

sub FIRSTKEY ($self) { return refuse("the keys of %INC (which modules perl loaded is not all chalk's)") }

sub NEXTKEY ($self, $last) { return refuse("the keys of %INC (which modules perl loaded is not all chalk's)") }

# refuse($why): a question chalk does not answer, stopped by name at run time.
sub refuse ($why) {
    print STDERR "chalk: refused at run time: $why\n";
    exit 255;
}

1;
