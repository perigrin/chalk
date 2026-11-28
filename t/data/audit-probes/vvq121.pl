my $t = "abc"; sub up { $_[0] = "Z"; $_[1] } print up(substr($t, 0, 1), $t), "$t\n";
