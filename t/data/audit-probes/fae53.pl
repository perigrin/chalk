my $t=""; for my $f (sub { 1 }, sub { die "b\n" }, sub { 3 }) { my $r = eval { $f->() }; $t .= defined $r ? $r : "E"; } print "$t\n";
