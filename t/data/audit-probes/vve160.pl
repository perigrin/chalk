my $r; sub f { 1 } f(@$r); print ref($r) || "none", "\n";
