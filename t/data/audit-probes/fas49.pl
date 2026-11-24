our $x=1; sub n { $x=7 } my $r=[$x, n(), $x]; print "@$r\n";
