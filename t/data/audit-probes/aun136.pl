my $x = 1; my $f = sub { $_[0] = 5 }; $f->($x); print "$x\n";
