my $s = \"str"; my $a = [1]; my $h = {}; my $c = sub {}; my $rr = \$s; print join(",", map { ref } $s, $a, $h, $c, $rr), "\n";
