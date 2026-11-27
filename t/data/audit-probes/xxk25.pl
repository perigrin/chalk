my $s = "abc"; sub up { $_[0] =~ tr/a-z/A-Z/ } my $n = up($s); print "$n$s\n";
