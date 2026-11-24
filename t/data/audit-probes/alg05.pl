my $r=[1,2]; eval { for my $x (@$r) { $x = "z"; last } }; print "@$r\n";
