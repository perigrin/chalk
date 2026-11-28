my $t = "a b"; sub id { "@_" } print id(split(" ", $t), $t = "z"), "\n";
