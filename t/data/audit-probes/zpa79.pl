my $s="abc"; sub f { substr($_[0],0,1)="z" } f($s); print "$s\n";
