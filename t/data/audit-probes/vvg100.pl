sub tw { my $f = shift; sub { $f->($f->(@_)) } } my $a3 = sub { $_[0] + 3 }; print tw($a3)->(1), "\n";
