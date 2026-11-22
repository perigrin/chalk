our $t = "a"; sub chg { $t = "b" } my $s = $t . (chg(), $t)[1]; print "$s\n";
