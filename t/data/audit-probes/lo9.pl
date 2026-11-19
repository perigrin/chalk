our $g = 1; my $f = sub { $g }; { local $g = 2; print $f->() } print $f->(), "\n";
