my $t = "ab"; sub id { "@_" } print id(join("", $t), $t = "z"), "\n";
