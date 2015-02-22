---
layout: post
redirect_from: "posts/mailserver/"
guid: "http://rampke.de/posts/mailserver/"
title: "Mailserver-Setup"
author: "Matthias Rampke"
---
{% include JB/setup %}



# Das Problem

Bisher liefen alle meine Mails über Google Mail, was an sich funktioniert, und ich wollte schon immer wissen wie man so seinen eigenen Mailserver aufsetzt und betreibt. Andererseits hatte ich davor immer einen Heidenrespekt – zurecht. Hier also was ich so rausgefunden und letztenendes getan habe; die ganzen gescheiterten Zwischenschritte werde ich nicht im Detail reproduzieren.

# Die Situation

Ich habe einen eigenen vServer von [Netcup](http://netcup.de/), nicht besonders dicke, aber tut gut seine Dienste. Darüber habe ich bisher schon Web- und Jabberserver betrieben. Es läuft Debian Testing.

Bisher lief auch ein [sendmail](http://sendmail.org/), der die Weiterleitungen (via [virtusertable](http://www.sendmail.com/sm/open_source/tips/virtual_hosting/) einiger @rampke.de-Mailadressen an meine Schwester, meinen Vater und meine Oma erledigt hat. Alles andere wurde via Catch-All-Regeln an meine [Google-Mail-Adresse](mailto:matthias.rampke@googlemail.com) weitergeleitet, auf dem Server selbst fand keine Filterung oder Speicherung statt. Alles in allem ein relativ einfaches Setup, weil die komplette Spamfilterungsproblematik bei den Empfänger\_innen erledigt wird.

# Das neue Setup

Nachdem ich ein bisschen hin- und hergelesen habe bin ich zu dem Schluss gekommen, dass es [postfix](http://www.postfix.org/) als zentraler Mailserver sein soll. Dazu kommen [Dovecot](http://dovecot.org) als IMAP-Server und [Roundcube](http://roundcube.net/) als Webmail-Client sein. Roundcube spricht IMAP mit Dovecot, das auf die [Maildir](http://en.wikipedia.org/wiki/Maildir)s zugreift, die postfix befüllt.

Die Spamfilterung brauchte ein wenig Experimentierung und hat auch am längsten gedauert. Letzten Endes lief es auf [postgrey](http://postgrey.schweikert.ch/) für [Greylisting](http://en.wikipedia.org/wiki/Greylisting) und [SpamAssassin](http://spamassassin.apache.org/) für weitergehende Spamfilterung hinaus. [DSpam](http://www.nuclearelephant.com/) hatte ich kurz am laufen, aber da hat sich beim Training eine mehrere Gigabyte große Datenbank angesammelt – und das pro spamgefilterter Mailadresse, und beim Versuch das einzudämmen habe ich das ganze irgendwie so zerschossen, dass gar nichts mehr ging. [Amavis](http://www.ijs.si/software/amavisd/) braucht unglaublich viel Speicher, was mir dafür, dass es letztlich nur die Anbindung für SpamAssassin sein sollte, doch etwas viel war. [Policyd](http://www.policyd.org/) habe ich nie zum laufen bekommen.

## DISCLAIMER

> Das hier ist ein Aufschrieb von dem, was ich auf meinem Server getan habe um meinen Mailserver-Ansprüchen gerecht zu werden, soweit ich es im Nachhinein und abzüglich aller Irrwege rekonstruieren konnte. Benutzernamen, Pfade etc. müssen auf jeden Fall angepasst werden, auch sonst kann ich nicht für Vollständigkeit und/oder Richtigkeit garantieren. Nehmt es als Hinweis, lest die Dokumentation dazu, und macht mir keine Vorwürfe wenn die Hausaufgaben den Hund fressen.

## Postfix

Postfix an sich zu installieren und einzurichten ist relativ einfach. Ich habe die Pakete `postfix`, `postfix-doc` und `postfix-pcre` installiert. Letzteres bringt Unterstützung für [Perl-kompatible reguläre Ausdrücke](http://en.wikipedia.org/wiki/PCRE). Postfix arbeitet viel mit Mappings (etwa: Mails an X@example.com werden weitergeleitet an Y@example.org und den lokalen Benutzer _Z_). Normalerweise werden dafür Hashtables verwendet, die nach jeder Änderung neu kompiliert werden müssen (`postmap <Datei>`) und relativ unflexibel sind; PCRE erlauben genauere Kontrolle was gematcht wird (reguläre Ausdrücke eben) und die eigentliche Quelldatei wird jedes mal auf's neue eingelesen, der Übersetzungsschritt entfällt also. Außerdem wird in verschiedenen Anleitungen zur Einbindung von Filtern so, dass sie nur auf eingehende Mails angewendet werden (etwas der Spamfilter) ein Umweg über eine PCRE-Tabelle gewählt; ob und warum das mit Hashtables nicht geht habe ich nicht untersucht.

Postfix hat zwei Haupt-Konfigurationsdateien: `master.cf` und `main.cf`. `master.cf` gibt an, aus welchen Diensten der gesamte Postfix-Komplex besteht; das umfasst etwa den `smtpd`, der eingehende Mail entgegen nimmt, den `qmgr`, der die internen Mail-Queues verwaltet und einige mehr. Eine ganze Reihe davon ist in Debian schon vorkonfiguriert und die lassen wir auch tunlichst in Ruhe. Nur für den Spamfilter werden wir später noch einen Dienst dort hinzufügen. `main.cf` ist die allgemeine Postfix-Konfigurationsdatei.

### Konfiguration

Die Debian-Standard-`main.cf` ist eine sehr gute Ausgangsbasis. Debian-üblich wird in `/etc/mailname` der für E-Mails relevante Domainname des Systems festgelegt; bei mir ist das _rampke.de_, während der Haupt-Domainname des Servers _2ktfkt.de_ ist. In `/etc/mailname` ist also `rampke.de` eingetragen. Dies wird dann auch von Postfix eingelesen.

Bei `smtpd_tls_cert_file` und `smtpd_tls_key_file` habe ich die Schlüssel- und Zertifikatsdateien eingetragen, die ich mir schon für Mail- und Jabberserver von [StartSSL](https://startssl.com/) geholt hatte. Als `mydestination` habe ich nur `localhost`, weil alle Domains durch virtuelle Benutzer abgedeckt werden sollen.

Da mein Server eine IPv6-Adresse hat, die auch im DNS steht, musste ich mit `inet_protocols = all` auch die IPv6-Unterstützung in Postfix aktivieren.

### Mailboxes und virtuelle Adressen

Das System für [virtuelle Adressen](http://www.postfix.org/VIRTUAL_README.html) gibt es bei Postfix in zwei Ausprägungen:

1. virtuelle Adressen, aber alle lokalen Benutzer entsprechen UNIX-Nutzerkonten
2. virtuelle Adressen und virtuelle Mailboxen

Da letzteres mehr Kontrolle bietet, wo die Mails letzten Endes abgeworfen werden, habe ich das gewählt. Dazu wird in `main.cf` definiert:

    virtual_mailbox_domains = pcre:/etc/postfix/hosts
    virtual_mailbox_base = /var/mail/vhosts
    virtual_alias_maps = pcre:/etc/postfix/virtual
    virtual_mailbox_maps = hash:/etc/postfix/vmailbox
    virtual_minimum_uid = 1000
    virtual_uid_maps = hash:/etc/postfix/vmailbox.uids
    virtual_gid_maps = hash:/etc/postfix/vmailbox.gids

`hosts` verwende ich mit PCRE, da ich auch alle Subdomains erfassen möchte, das sieht dann so aus:

/^(.+\.)?rampke\.de$/ NONE
/^(.+\.)?2pktfkt\.de$/ NONE
/^(.+\.)?2pktfkt\.net$/ NONE
/^(.+\.)?grade\.so$/ NONE

Wenn das nicht nötig ist, genügt auch `virtual_mailbox_domains = /etc/postfix/hosts` und `hosts` ist dann einfach eine Liste der Domainnamen, einer pro Zeile. Das NONE hat keine Funktion, außer hässliche Warnungen im Log zu ruhigzustellen.

Mail, die lokal zugestellt wird, soll Postfix im Maildir-Format ablegen. Was wohin kommt, definiere ich in der Hashtabelle `vmailboxes` – nicht vergessen: nach jeder Änderung mit `postmap vmailboxes` die Datenbank dazu aktualisieren. Das sieht dann so aus:

    archive matthias/.Archive/
    local   matthias/
    matthias  matthias/
    spam    matthias/.Junk/

`archive` entspricht einem zusätzlichen Maildir, in dem jede Mail, die ich bekomme, noch einmal abgelegt wird. Ich bin mit GMail sozialisiert und gewöhnt, dass eine Mail nicht wirklich weg ist, wenn ich sie aus der Inbox lösche. `local` und `matthias` zeigen schlicht auf das Haupt-Maildir. Die Pfade sind relativ zu `virtual_mailbox_base`.

In `virtual` werden die vielfältigen Weiterleitungen kreuz und quer durch die Weltgeschichte festgelegt:

    /^matthias([+-_].+)?@(.+\.)?rampke\.de$/ matthias.rampke@googlemail.com, matthias, archive
    /^matthias([+-_].+)?@(.+\.)?2pktfkt\.de$/ matthias.rampke@googlemail.com, matthias, archive
    /^matthias([+-_].+)?@(.+\.)?2pktfkt\.net$/ matthias.rampke@googlemail.com, matthias, archive
    /^matthias([+-_].+)?@(.+\.)?grade\.so$/ matthias.rampke@googlemail.com, matthias, archive

    /^.*\+spam@.*$/ spam

    # /etc/aliases
    /^mailer-daemon@/ postmaster
    /^postmaster@/ root
    /^nobody@/ root
    /^hostmaster@/ root
    /^usenet@/ root
    /^news@/ root
    /^webmaster@/ root
    /^www@/ root
    /^ftp@/ root
    /^abuse@/ root
    /^noc@/ root
    /^security@/ root
    /^root@/ matthias
    /^m@/ matthias
    /^clamav@/ root

Der erste Teil legt fest, dass alle Mails, die an _matthias@..._ bei einer meine Domains gehen, in meinem Google-Mail-Postfach, der Inbox und dem Archiv-Maildir abgelegt werden. Der zweite Teil leitet eine Reihe von Standard-Adressen an `matthias` weiter. Was an _spam@rampke.de_ geht wird direkt im Junk-Ordner abgelegt.

In `vmailbox.uids` und `vmailbox.gids` sind die Benutzer-IDs festgelegt, mit denen die Mails in die Mailboxen einsortiert werden:

    matthias    1000
    local       1000
    archive     1000
    spam        1000
    @rampke.de  65534

65534 ist der Benutzer _nobody_; da sollte niemals Mail ankommen und die soll auch nirgends hingeschrieben werden.

Noch ein `sudo /etc/init.d/postfix restart` und der Mailserver läuft. Falls etwas schiefgegangen ist, steht das in `/var/log/mail.log`.

## Dovecot

Zuerst muss Dovecot wissen, wo es die Mails findet; dazu setze ich in `/etc/dovecot/conf.d/10-mail.conf`

    mail_location = maildir:/var/mail/vhosts/%u

Die anderen Einstellungen dort können bleiben. In `10-auth.conf` wird festgelegt, wer sich per IMAP einloggen darf und worüber; bis auf weiteres sollen sich nur Systembenutzer einloggen können, das ist die Standardeinstellung. In `10-ssl.conf` konnte ich wieder SSL-Schlüssel und -Zertifikat eintragen:

    ssl_cert = </etc/ssl/certs/rampke.de.crt
    ssl_key = </etc/ssl/private/rampke.de.key

Damit ist auch festgelegt, dass ich in meinen Mailprogrammen immer _rampke.de_ als IMAP- und SMTP-Server eintrage, damit sich die Clients nicht über unpassende Zertifikate beschweren. *Achtung:* nicht in allen Android-Versionen ist _StartSSL_ als Certificate Authority eingetragen, mein Telefon beschwert sich also immer bzw. ich muss die Zertifikatsüberprüfung im Mailprogramm abschalten. -_Isebensokammanixmachen_.

Dovecot ist damit schon fertig konfiguriert, aber wir können Postfix jetzt auch Authentifizierung und Verschlüsselung für SMTP-Verbindungen per [SASL](http://www.postfix.org/SASL_README.html) beibringen. Dazu kommt in `/etc/postfix/main.cf`

    smtpd_sasl_type = dovecot
    smtpd_sasl_path = private/auth
    smtpd_sasl_auth_enable = yes

und in `/etc/dovecot/conf.d/10-master.conf` wird im Bereich `service auth` hinzugefügt

    unix_listener /var/spool/postfix/private/auth {
      mode = 0666
    }

Derart gegenüber Postfix authentifizierte Clients können dann auch Mails nach außerhalb verschicken.

Eine letzte Runde Neustarts

    /etc/init.d/dovecot restart
    /etc/init.d/postfix restart

und auch der IMAP-Zugriff sollte klappen. (Jetzt ist der Zeitpunkt gekommen, den Mailclient einzurichten und ein paar Testmails hin- und herzuschicken. Immer gut ist auch, die Abläufe per `tail -f /var/log/mail.log` zu beobachten.)

## Roundcube

An Roundcube selbst ist nicht viel zu konfigurieren, ich habe lediglich das `roundcube`-Paket installiert und in die entsprechende Apache-Site

    Alias /mail/program/js/tiny_mce/ /usr/share/tinymce/www/
    Alias /mail /var/lib/roundcube

eingetragen.

    /etc/init.d/apache2 reload

nicht vergessen.

## Postgrey

Greylisting ist eine relativ einfache und halbwegs effektive Methode, um zumindest sehr primitiv versendeten Spam abzuhalten: wenn der Absender nicht bekannt ist, wird er erst einmal mit einer temporären Fehlermeldung wieder weggeschickt; korrekterweise probiert er es dann später noch einmal und wird zugelassen. Für die meisten Spammer ist das schon zu viel Aufwand und lohnt sich nicht mehr.

Postgrey kommt auf Debian im Paket `postgrey` und ist an sich schon weitgestehend fertig konfiguriert. Da ich aber wollte, dass möglichst alle interne Kommunikation per UNIX-Sockets, nicht per TCP/IP abläuft, habe ich in `/etc/default/postgrey` die `POSTGREY_OPTS` zu

    POSTGREY_OPTS="--unix=/var/spool/postfix/private/postgrey"

geändert. Damit Postgrey dort hin schreiben darf, muss der Benutzer `postgrey` aber noch zur Gruppe `postfix` hinzugefügt werden

    adduser postgrey postfix

und die Verzeichnisrechte angepasst werden

    chmod 770 /var/spool/postfix/private

Nun muss Postgrey nur noch in Postfix eingebunden werden; dazu werden in `/etc/postfix/main.cf` explizit Regeln für den Empfang von E-Mails angegeben:

    smtpd_recipient_restrictions =
        permit_mynetworks
        permit_sasl_authenticated
        reject_unauth_destination
        check_policy_service unix:private/postgrey

`permit_mynetworks` erlaubt lokalen Benutzern (oder, falls weiter oben geändert, IPs aus bestimmten Subnetzen) den uneingeschränkten Zugriff, also u.A. Mails nach außen zu verschicken. `permit_sasl_authenticated` legt das selbe für per SASL-authentifizierte Verbindungen fest. Sollte keiner dieser Fälle greifen, wird per `reject_unauth_destination` jede Mail, für die sich Postfix nicht explizit (durch Festlegung in `/etc/postfix/hosts`) zuständig fühlt, verworfen. Was dann noch durchkommt, sind also Mails von außen, die empfangen werden sollen – nach dem Greylisting eben.

Mit

    /etc/init.d/postgrey restart
    /etc/init.d/postfix restart

werden die Änderungen aktiv.

## SpamAssassin

Nachdem ich einiges rumprobiert habe hat sich SpamAssassin als einfachste und praktikabelste Lösung rausgestellt. Die Installation erfolgt via dem `spamassassin`-Paket; `spamc` wird gleich als Abhängigkeit mit installiert. Die Einrichtung folgt lose [dieser Anleitung](http://www.debuntu.org/postfix-and-pamassassin-how-to-filter-spam)

### spamd

Zunächst muss in `/etc/default/spamassassin` der _spamd_ aktiviert werden:

    ENABLED=1

SpamAssassin liefert einen Cronjob mit, der täglich aktualisierte Regellisten herunterlädt und die Spamdatenbank aufräumt. Um den zu aktivieren, in der selben Datei

    CRON=1

setzen. _spamd_ soll ebenfalls unter einem eigenen Benutzer laufen, was diesmal von Debian nicht automatisch eingerichtet wird. Also legen wir einen an:

    adduser --system --home /var/lib/spamassassin --disabled-password --no-create-home --group spamd2Adding
    chown -R spamd:spamd /var/lib/spamassassin

und passen `/etc/default/spamassassin` an

    OPTIONS="--create-prefs --max-children 1 --username spamd --helper-home-dir"

`--max-children 1` begrenzt die Anzahl von Prozessen, die Spamd gleichzeitig startet, auf das Minimum, da jeder davon ziemlich viel Speicher frisst und bei dem Mailaufkommen auf meinem Server das allemal reicht.

An der eigentlichen SpamAssassin-Konfiguration in `/etc/spamassassin` muss erstmal nichts geändert werden.

### Einbindung in Postfix

Um SpamAssassin in Postfix einzubinden, kommt ans Ende von `/etc/postfix/master.cf`

    spamassassin unix -     n       n       -       -       pipe
        user=spamd argv=/usr/bin/spamc -f -e
        /usr/sbin/sendmail -oi -f ${sender} ${recipient}

und in die neu anzulegende Datei `/etc/postfix/spamassassin`

    /./ FILTER spamassassin:spamassassin

`/./` ist wieder eine PCRE, die festlegt wann der Spamfilter anspringt. In dieser Variante wird er dann für jede eingehende Mail verwendet, z.B. mit `/^matthias([+-_].+)?@/` nur für die Mails an mich. Im `master.cf`-Eintrag ist festgelegt, dass auch `spamc` als Benutzer `spamd` ausgeführt wird und die gefilterten Mails via `sendmail` wieder in die Verarbeitung eingeschleust werden. `sendmail` wird von Postfix bereitgestellt und fügt die Mails _nach_ allen Filtern ein, es entsteht also keine Endlosschleife.

Zu guter Letzt muss dieser Filter noch in `/etc/postfix/main.cf` eingebunden werden, indem die `smtpd_recipient_restrictions` erweitert werden:

    smtpd_recipient_restrictions =
        permit_mynetworks
        permit_sasl_authenticated
        reject_unauth_destination
        check_policy_service unix:private/postgrey
        check_recipient_access pcre:/etc/postfix/spamassassin

### Training

SpamAssassin benutzt auch Bayes-Filter, die mit Spam- und Nicht-Spam-('_Ham_'-)Mails trainiert werden sollten. Dazu braucht man einen vernünftigen Korpus an ebensolchen, etwa den [2006 TREC Public Spam Corpus](http://plg.uwaterloo.ca/~gvcormac/treccorpus06/). Darin sind einige zehntausend Spam- und Ham-Mails enthalten, die wir aber erstmal in verschiedene Ordner auseinandersortieren:

    tar xzf trec06p.tgz
    cd trec06p/full
    awk 'BEGIN { print "rm -rf spam ham; mkdir -p ham spam" } /ham.*/ { split($2,a,"/"); print( "ln " $2 " ham/" a[3]a[4]); } /spam.*/ { split($2,a,"/"); print( "ln " $2 " spam/" a[3]a[4]); }' index | sh
    cd ../..

Die Mails liegen jetzt als einzelne, nummerierte Dateien in `trec06p/full/spam` und `trec06p/full/ham`, nun kann SpamAssassin damit gefüttert werden:

    su spamd -s /bin/sh -c "/usr/bin/sa-learn --ham --progress trec06p/full/ham/"
    su spamd -s /bin/sh -c "/usr/bin/sa-learn --spam --progress trec06p/full/spam/"

Kaffeepausenzeit. Ich habe zusätzlich auch mittels `getmail` (gleichnamiges Paket) meine Mails von GMail in mein Archiv-Maildir geladen. Dazu kommt in `/home/matthias/.getmail/getmailrc`

    [retriever]
    type = SimplePOP3SSLRetriever
    server = pop.gmail.com
    username = matthias.rampke
    password = PASSWORT

    [destination]
    type = Maildir
    path = /var/mail/vhosts/matthias/.Archive

und in den [GMail-Einstellungen](https://mail.google.com/mail/u/0/#settings/fwdandpop) muss natürlich POP3 für alle Mails aktiviert sein. Dann einfach mit mit `getmail` laden (so sind sie dann auch per IMAP und Roundcube wieder verfügbar) und SpamAssassin damit füttern:

    su matthias -c getmail
    chmod -R g+r /var/mail/vhosts/matthias/.Archive/new /var/mail/vhosts/matthias/.Archive/cur
    adduser spamd matthias
    su spamd -s /bin/sh -c "/usr/bin/sa-learn --ham --progress /var/mail/vhosts/matthias/.Archive/new /var/mail/vhosts/matthias/.Archive/cur"
    chmod -R g-r /var/mail/vhosts/matthias/.Archive/new /var/mail/vhosts/matthias/.Archive/cur
    deluser spamd matthias

Die `chown`-/`adduser`-Zirkelei ist nötig, damit `sa-learn` auch als Benutzer `spamd` die Mails einlesen kann. Vorsicht mit dem vielen Kaffee! Das kann jetzt alles im Hintergrund weiterlaufen, braucht aber vergleichsweise viel RAM.

## DomainKeys Identified Mail

[DKIM](http://www.dkim.org/) ist ein Verfahren, um durch im DNS hinterlegte öffentliche Schlüssel zu beweisen, dass man berechtigt ist, Mails von einer bestimmten Domain (bspw. `rampke.de`) zu versenden. SpamAssassin bezieht das in die Spam-Bewertung bereits mit ein, hier geht es nun darum, ausgehende Mail zu signieren.

> *Warnung:* Falls Mails von dieser Domain auch über andere SMTP-Server verschickt werden, kann die Deklaration der [Author Domain Signing Practices](http://www.rfc-editor.org/rfc/rfc5617.txt) dazu führen, dass diese mit erhöhter Wahrscheinlichkeit als Spam klassifiziert werden. Google Mail erlaubt, andere Mailadressen (nach Verifikation) als Absender zu verwenden, gibt aber im _Sender:_-Header die GMail-Adresse an und fügt eine DKIM-Signatur für _gmail.com_ bzw. _googlemail.com_ hinzu, so dass die Mails als gültig signiert durchgehen; ich weiß nicht wie das bei anderen Webmail-Diensten ist.

Die Signierung wird durch das Paket `dkim-filter` erledigt. Der DKIM-Dienst spricht dann das (ursprünglich für Sendmail entwickelte) [_milter_](http://www.postfix.org/MILTER_README.html)-Protokoll mit Postfix. Die Einrichtung folgt lose [dieser](https://help.ubuntu.com/community/Postfix/DKIM) und [jener](http://www.howtoforge.com/set-up-dkim-for-multiple-domains-on-postfix-with-dkim-milter-2.8.x-centos-5.3) Anleitung.

Zuerst stelle ich in `/etc/default/dkim-filter` ein, dass die Kommunikation über einen UNIX-Socket laufen soll:

    SOCKET="local:/var/spool/postfix/private/dkim"

und füge `dkim-filter` zur `postfix`-Gruppe hinzu, wie auch schon `postgrey`:

    adduser dkim-filter postfix

Dann erzeuge ich die DKIM-Keys für meine Domains:

    mkdir -p /etc/dkim; cd /etc/dkim
    for d in 2pktfkt.de 2pktfkt.net rampke.de grade.so; do
        mkdir $d; cd $d
        dkim-genkey -t -s mail -d $d
        mv mail.private mail
        chmod 0400 mail
        cd ..
    done

Die privaten Schlüssel liegen jetzt jeweils in `/etc/dkim/<Domain>/mail`, wobei _mail_ der DKIM-Selektor ist. `dkim-filter` braucht nun eine Liste dieser Schlüssel, die ich in `/etc/dkim/keylist` ablege:

    *@rampke.de:rampke.de:/etc/dkim/rampke.de/mail
    *@2pktfkt.de:2pktfkt.de:/etc/dkim/2pktfkt.de/mail
    *@2pktfkt.net:2pktfkt.net:/etc/dkim/2pktfkt.net/mail
    *@grade.so:grade.so:/etc/dkim/grade.so/mail

Jetzt kann das ganze auch in `/etc/dkim-filter.conf` eingetragen werden:

    UMask                   000
    Domain                  rampke.de, 2pktfkt.de, 2pktfkt.net, grade.so
    KeyList                 /etc/dkim/keylist

`UMask 000` ist notwendig, damit Postfix den Socket benutzen kann. Der Rest von `dkim-filter.conf` kann so bleiben. Schlussendlich erzählen wir Postfix in `/etc/postfix/main.cf` noch davon

    milter_default_action = accept
    milter_protocol = 2
    smtpd_milters = unix:private/dkim
    non_smtpd_mitlers = unix:private/dkim

Und starten `dkim-filter` und `postfix` neu

    /etc/init.d/dkim-filter restart
    /etc/init.d/postfix restart

Von nun an sollten Mails, die über diesen SMTP-Server verschickt werden, signiert sein, d.h. einen `DKIM-Signature:`-Header haben. Damit andere die Signatur auch überprüfen können, muss für jede Domain ein _TXT_-Record `mail._domainkey.<Domain>` eingerichtet werden; was genau da rein muss steht jeweils in `/etc/dkim/<Domain>/mail.txt`. Optional kann auch noch mitgeteilt werden, dass Empfänger erwarten sollen, dass alle Mails von dieser Domain signiert sind; dazu wird im _TXT_-Record für `_adsp._domainkey.<Domain>`

    dkim=all

eingetragen.

Um DKIM zu testen, kann man eine Mail an <autorespond+dkim@dk.elandsys.com> schicken (Betreff und Inhalt egal) und bekommt das Ergebnis der Signaturüberprüfung zurückgemailt.

# Fazit

Einen Mailserver mit allem drum und dran aufsetzen geht, aber ist definitiv nicht einfach. Am längsten hat für mich die Suche nach einer funktionierenden Spamfilterlösung gedauert, alles in allem waren es knapp drei Tage. Beim nächsten Mal geht's dann hoffentlich schneller. Falls irgendwas so nicht stimmt oder nicht funktioniert, mailt mir: <matthias@rampke.de>
