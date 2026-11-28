my $t = "ab"; sub id { "@_" } print id(sprintf("%s", $t), $t = "z"), "\n";
