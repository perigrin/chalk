sub z { $_[0] = "z" } my $r = [1]; z($r->[0]); z($$r[1]); print "@$r\n";
