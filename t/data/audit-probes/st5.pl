my $a = defined(&foo) ? 1 : 0; *foo = sub { 1 }; my $b = defined(&foo) ? 1 : 0; print "$a$b\n";
