my $s="a"; sub n { $s.="b"; "" } my $r = join("", $s, n(), $s); print "$r\n";
