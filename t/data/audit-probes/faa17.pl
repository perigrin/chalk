our $x=1; sub f { my $r=shift; $$r++ } f(\$x); print "$x\n";
