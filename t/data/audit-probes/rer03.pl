use feature "try"; no warnings; our $g=1; sub f { try { return 5 } catch ($e) { } finally { $g=2 } } f(); print "$g\n";
