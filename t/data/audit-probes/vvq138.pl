my $t = "abc"; sub id { "@_" } print id(length($t), $t = "z"), "\n";
