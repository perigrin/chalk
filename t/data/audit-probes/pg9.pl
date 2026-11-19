our %cfg = (v => 1); sub set { $cfg{v} = $_[0] } my $a = $cfg{v}; set(2); my $b = $cfg{v}; print "$a$b\n";
