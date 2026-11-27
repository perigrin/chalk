my $x=1; my ($g,$s) = (sub { $x }, sub { $x = $_[0] }); $s->(5); my $v = $g->(); $x = 6; print "$v", $g->(), "\n";
