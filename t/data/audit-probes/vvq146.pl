my $t = "ab"; sub id { "@_" } print id(ucfirst($t), lcfirst($t), $t = "z"), "\n";
