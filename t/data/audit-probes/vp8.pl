my $o = { n => 0 }; sub inc { $_[0]{n}++; $_[0]{n} } my $t = inc($o) * 10 + inc($o); print "$t\n";
