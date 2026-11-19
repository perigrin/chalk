sub mk { my $c = shift; return sub { return $c++ } } my $f = mk(5); my $g = mk(10); $f->(); print $f->(), " ", $g->(), "\n";
