my $x=1; my $f = sub { $x }; $x=2; print $f->(), "\n";
