my $s = "abc"; sub ed { $_[0] =~ s/b/z/ } ed($s); sub ed2 { my $r = shift; $$r =~ tr/a/y/ } ed2(\$s); print "$s\n";
