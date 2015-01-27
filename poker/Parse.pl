#!/usr/local/bin/perl

use MSSQL::Sqllib;
use strict;

$| = 1;
require 'Cards.pl';
require 'DBUtils.pl';

use vars qw / $GameID $HandID %Pla %Player $SmallBet $BigBet %AllIn $open/;
use vars qw / @RoundDesc @Rounds $SiteID $Redo $prevbet $PlNb/;

@RoundDesc = qw / PreFlopDesc FlopDesc TurnDesc RiverDesc /;
@Rounds = qw / PreFlop Flop Turn River /;


sql_init('Caramou', 'sa', '', 'Poker');

$SiteID = GetSite('PartyPoker');

if ($ARGV[0] eq '-d') {
    shift;
    $::Debug = 1;
}

while (my $ff = shift @ARGV) {
    my @files;
    if (-d $ff) {
		opendir DIR, $ff;
		@files = map { "$ff\\$_" } grep {/txt$/} readdir DIR;
		closedir DIR;
    } else {
		$files[0] = $ff;
    }
    foreach my $f (@files) {
		open IN, $f;
		print "file $f\n";
		while (<IN>) {
			last if (/Hand History for Game (\d+)/);
		}

		($HandID) = /Hand History for Game (\d+)/;
		print "Game $HandID\r";

		while (ParseHand($1)) {
			($HandID) = /Hand History for Game (\d+)/;
			print "Game $HandID\r";
			last if (eof(IN));
		}
		close IN;
    }
}

sub Debug {
    return unless ($::Debug);
    print @_;
}

sub ParseTable {
    $_ = <IN>;
    s/^>//;
    my ($signature, $TableName,$Type);
    my ($sb, $bb, $post, %DeferHands,$date,$time,$year);
    ($SmallBet,$BigBet,$signature,$Type,$date,$time,$year) = /^([0-9\.]+)\/([0-9\.]+) (\S+) (\(.*?\))?\s+\- ... (.*) (..:..:..) EDT (\d+)/;
    Debug "$1 / $2 --- $3 <($SmallBet,$BigBet,$signature,$Type,$date)>\n";
    return 0 unless ($signature eq 'TexasHTGameTable');
    $_ = <IN>;

    ($TableName) = /Table (.*) \(Real Money\) -- Seat (\d+) is the button/;
    $TableName =~ s/Card Room //;
    $TableName = join('',split(/\s+/,$TableName));

    $_ = <IN>;

    /Total number of players : (\d+)/;
    while (<IN>) {
		last unless (/Seat (\d+): (.*) \( \$(\d+(\.\d+)?)\)/);
		$Player{$2}{Ref} or $Player{$2}{Ref} = GetPlayer($2);
		Debug "Seat $1, Player $2 ($Player{$2}{Ref})\n";
		$DeferHands{$2}++;
    }
    $prevbet = 0;
    until (/Dealing down cards/) {
	
		s/^>//;

		if (($sb) = (/(.*)  posts small blind/)) {
			Debug "SB: [$sb]\n"; 
			$Player{$sb}{Ref} or $Player{$sb}{Ref} = GetPlayer($sb);
			$Player{$sb}{Pos} = 1;
			$DeferHands{$sb}++;
		} elsif (($bb,$post) = /(.*)  posts big blind + dead \(([0-9\.]+)\)/) {
			Debug "BB+Dead: [$bb]\n"; 
			$Player{$bb}{Ref} or $Player{$bb}{Ref} = GetPlayer($bb);
			$Player{$bb}{Pos} = 2 unless ($prevbet);
			$prevbet = $SmallBet;
			$DeferHands{$bb}++;
		} elsif (($bb,$post) = /(.*)  posts big blind \(([0-9\.]+)\)/) {
			Debug (($prevbet ? 'Post' : 'BB') . ": [$bb] $post\n"); 
			$Player{$bb}{Ref} or $Player{$bb}{Ref} = GetPlayer($bb);
			$Player{$bb}{Pos} = 2 unless ($prevbet);
			$SmallBet ||= $post;
			$prevbet = $SmallBet;
			Debug "prevbet set to $prevbet ($SmallBet / $post)\n";
			$DeferHands{$bb}++;
		} elsif (/(.*) is sitting out/) {
			delete $DeferHands{$1};
		}
		$_ = <IN>;
    }
    my $g = FindGames($TableName,$signature,$Type,$SmallBet,($SmallBet*2));
    return 0 unless ($g->{GameID} > 0);
    $GameID = $g->{GameID};
    $SmallBet ||= $g->{BigBlind};

    if (NewHandHistory("$date, $year $time")) {
		$Redo = 0;
		IncPlayer('Hands',$_) foreach (keys %DeferHands);
    } else {
		$Redo = $HandID;
    }
    return 1;
}

sub Translate {
    my ($what,$howmuch,$when) = @_;

    my $res;
    ($what eq 'folds.') and $res =  '-';
    ($what eq 'checks.') and $res =  '=0';
    if ($what eq 'raises') {
		$howmuch -= $prevbet;
		$prevbet = $howmuch;
		$howmuch /= $SmallBet;
		$howmuch /= 2 if ($when > 1);
		$howmuch = 1 unless ($howmuch);
		$res = "+$howmuch";
    } else {
		$what eq 'bets' and $prevbet = $howmuch;
		$howmuch /= $SmallBet;
		$howmuch /= 2 if ($when > 1);
		($what eq 'bets') and $res =  " $howmuch";
		($what eq 'calls') and $res =  "=$howmuch";
    }
    $res;
}

sub ParseBettingRound {
    my $nb = shift;
    my %Pla;
    my %Act;
    my $i = 3;
    while (<IN>) {
		chomp;
		s/^>//;
		last if (/^\*\* /);
		if (/(.*) ((calls (all-In\.|\(\d+(\.\d+)?\)))|(raises \(.*\) to .*)|folds\.|checks\.|(bets \(\d+(\.\d+)?\)))$/) {
			my ($name,$action,$act,$value);
			($name,$act) = ($1,$2);
			Debug ("$nb: $name -> $act\n");
			if ($act =~ /bets|raises|calls/) {
				($action,$value) = ($act =~ /(\S+)[^0-9]*([\.0-9]+).*?$/);
			} else {
				$action = $act;
			}
			if ($nb == 0) {
				unless ($open) {
					if ($action eq 'calls') {
						$Player{$name}{OpenCall}++;
						IncPlayer('OpenCall',$name,$GameID);
						$open = 1;
					} elsif ($action eq 'raises') {
						$Player{$name}{OpenRaise}++;
						IncPlayer('OpenRaise',$name,$GameID);
						$open = 1;
					}
				}
				unless (defined $Pla{$name} or $Player{$name}{Pos}) {
					$Player{$name}{Pos} = $i++;
				}
			}
			if ($act eq 'calls all-In.') {
				$AllIn{$name} = 1;
			} else {
				push @{$Act{$name}}, Translate($action,$value,$nb);
				$Pla{$name}++;
				$Pla{$name} = 0 if ($action eq 'folds');
			}
		}
	}
    my @ai = keys %AllIn;
    Debug "All In Players = [@ai]\n" if (@ai);
    map { ($AllIn{$_} and not $Pla{$_}) and ($Pla{$_} = 1 and $Act{$_} = [ '=*' ]) } keys %Player;
    my @who = sort { $Player{$a}{Pos} <=> $Player{$b}{Pos} } keys %Pla;
    $nb or splice(@who,0+@who,0,splice(@who,0,2));
    foreach (@who) {
		$Player{$_}{Hand}[$nb]++ if ($Pla{$_} > 0);
		$Player{$_}{Hand}[4]++ unless ($nb);
		AddPlayerHandHistory($_,$nb,join(',', @{$Act{$_}}));
		IncPlayer("$Rounds[$nb]s",$_) if ($nb > 0);
		AddPlayerAction($_,$nb,$Act{$_});
    }
    if (/Summary/) {
		Debug "---\n";
		return 0;
    }
    my ($cards) = /\[ (.*) \]/;
    $cards =~ s/,//g;
    
    if ($nb) {
		sql("update HandHistory set $Rounds[$nb+1] = '$cards' where 
                    HandNumber = $HandID and GameRef = $GameID");
    } else {
		my $flopid = Cards::NewFlop(split / /,$cards);
		$PlNb = 0+@who;
		sql("update HandHistory set $Rounds[$nb+1] = '$cards', 
                                    FlopRef = $flopid        where 
                HandNumber = $HandID and GameRef = $GameID");
    }
    1;
}

sub SkipHand {
    while (<IN>) {
		last if (/Hand History for Game/);
    }
}

sub ParseSummary {
    $open = 0;
    my ($pot, $side, $rake);
    while (1) {
		last if (/Hand History for Game/ or eof(IN));
		s/^>//;
		if (/Main Pot:/) {
			if (/Main Pot: \$(.*?) \| Rake: \$(.*)/) {
				($pot,$rake) = ($1,$2);
				Debug("Final pot: $pot ($rake)\n");
			} 
			if (/Main Pot: \$(.*?) \| (.*) \| Rake: \$(.*)/) {
				($pot,$rake) = ($1,$3);
				my @tmp = ($2 =~ /Side Pot \d+: \$(.*?) /g);
				map { $pot += $_ } @tmp;
				Debug("Final pot: $pot [@tmp] ($rake)\n");
			}
			sql("update HandHistory set FinalPot = $pot, RakeAmount = $rake
							where HandNumber = $HandID and GameRef = $GameID");
			$_ = <IN>;
			next;
		} elsif (/ balance \$/) {
			my $bal;
			$bal = <IN>; 
			chomp;    $bal =~ s/^>//;
			$_ .= $bal if ($bal =~ /\]$/ and $bal !~ / balance /);

			if (/(\S*) .* collected .*? net \+\$([\.0-9]+?) \[ (.{5})/) {
				my ($pl,$am) = ($1,$2);
				my ($hc, $ht, $hg) = AddHoleCards($3);
				my $PosDef = $Cards::PosDef[$PlNb - 2]->[$Player{$pl}{Pos} - 1];
				$Player{$pl}{Wins}++;
				Debug "$pl won $am with $hc ($ht)\n";

				sql("update PlayerHandHistory set HoleCards = '$hc',
													  HandType = '$ht',
													  PosDef = '$PosDef',
													  Class = $hg,
													  Result = $am
							where HandID = $HandID and 
								  PlayerID = $Player{$pl}{Ref}");
				sql("update HandHistory set WinnerRef = $Player{$pl}{Ref}
							where HandNumber = $HandID and
								  GameRef = $GameID");
				IncPlayer('Wins',$pl);
				IncPlayer('Showdowns',$pl);
			} elsif (/(.*) balance .* collected .* net \+\$(.*)/) {
				$Player{$1}{Wins}++;
				Debug "$1 won, no showdown\n";
				sql("update PlayerHandHistory set Result = $2
							where HandID = $HandID and 
								  PlayerID = $Player{$1}{Ref}");
				sql("update HandHistory set WinnerRef = $Player{$1}{Ref}
							where HandNumber = $HandID and
								  GameRef = $GameID");
				IncPlayer('Wins',$1);
			} elsif (/(.*) balance .* lost \$(.*?) \[ (.{5})/) {
				my ($pl, $am) = ($1, $2);
				my ($hc, $ht, $hg) = AddHoleCards($3);
				my $PosDef = $Cards::PosDef[$PlNb - 2]->[$Player{$pl}{Pos} - 1];
				Debug "$pl lost $am with $hc ($ht)\n";
				sql("update PlayerHandHistory set HoleCards = '$hc',
													  HandType = '$ht',
													  PosDef = '$PosDef',
													  Class = $hg,
													  Result = -$am
							where HandID = $HandID and 
								  PlayerID = $Player{$pl}{Ref}");
				IncPlayer('Showdowns',$pl);
			} elsif (/(.*) balance .* lost \$(.*?) \(folded\)/) {
				sql("update PlayerHandHistory set Result = -$2
							where HandID = $HandID and 
								  PlayerID = $Player{$1}{Ref}");
			}
			if (/(.*) balance /) {
				$Player{$1}{Pos} = 0;
				delete $AllIn{$1};
			}
			$_ = $bal;
		} else {
			$_ = <IN>;
		}
    }
}

sub ParseHand {
    if (ParseTable()) {
		my ($who,$c1,$c2);
		until (($who,$c1,$c2) = /Dealt to (.*) \[ (..), (..) \]/) { 
			$_ = <IN>; 
		}
		Debug "Hole cards: $c1 and $c2 -->$_\n";
		$Player{$who}{Ref} or $Player{$who}{Ref} = GetPlayer($who);

		ParseBettingRound(0) &&
			ParseBettingRound(1) && 
			ParseBettingRound(2) &&
				ParseBettingRound(3);
		my ($hc, $ht, $hg) = AddHoleCards("$c1 $c2");
		my $PosDef = $Cards::PosDef[$PlNb - 2]->[$Player{$who}{Pos} - 1];
		sql("update PlayerHandHistory set HoleCards = '$hc',
											  HandType = '$ht',
											  PosDef = '$PosDef',
											  Class = $hg
							where HandID = $HandID and 
								  PlayerID = $Player{$who}{Ref}");
		ParseSummary();
	} else {
		SkipHand;
    }
    1;
}
