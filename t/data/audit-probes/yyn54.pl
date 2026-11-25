print "tab\there", length("a\tb"), "q\"q", 'single $x\n', "nl\\n", "\x41\x{42}\103", "\e" eq chr(27) ? "esc" : "", "a\0b" eq "a" . chr(0) . "b" ? "nul" : "", "\n";
