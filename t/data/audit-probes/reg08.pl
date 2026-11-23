our $g=1; sub f { $g=5; 1 } my $r=[$g, f(), $g]; print "@$r\n";
