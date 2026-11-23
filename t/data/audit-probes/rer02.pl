use feature "defer"; no warnings; our $g=1; sub f { defer { $g=2 } return 5 } f(); print "$g\n";
