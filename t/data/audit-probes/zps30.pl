my $v; for (1..3) { $v = $v ? {a=>1} : 5 } print ref($v) || $v, "\n";
