my $t = "ab"; sub id { "@_" } print id(ord($t), chr(65), $t = "z"), "\n";
