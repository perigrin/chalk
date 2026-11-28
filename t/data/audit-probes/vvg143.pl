my $c = sub { "c@_" }; my @t = ($c); my %t = (k => $c); print $t[0]->(1), $t{k}->(2), "\n";
