my $x=1; my $f=sub { $x=2; $_[0] }; print $f->($x),"\n";
