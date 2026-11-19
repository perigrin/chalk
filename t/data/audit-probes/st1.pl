my $a = $ENV{AUDITX} // "u"; $ENV{AUDITX} = "v"; my $b = $ENV{AUDITX} // "u"; print "$a$b\n";
