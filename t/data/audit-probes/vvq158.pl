my $t = 4; sub id { "@_" } print id(defined($t), ref(\$t), $t = 9), "\n";
