our $g=1; my $f=sub { $g }; sub w { local $g=2; $_[0]->() } print w($f), $f->(), "\n";
