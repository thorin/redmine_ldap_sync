#!/usr/bin/ruby
rng = Random.new(12345)

puts <<MSG 
dn: ou=Group,dc=redmine,dc=org
ou: Group 
objectClass: organizationalUnit

MSG
# >>

user = <<MSG
dn: uid=%{username},ou=Person,dc=redmine,dc=org
mail: %{mail}
uid: %{username}
cn: %{cn}
preferredLanguage: %{language}
uidNumber: %{uidNumber}
gidNumber: 100
homeDirectory: /home/%{homeDir}
objectClass: posixAccount
objectClass: person
objectClass: inetOrgPerson
givenName: %{givenName}
sn: %{sn}
userPassword: {SSHA}Si9/UcgqKWBlN/+SQb+X1IHZnokzaicm 
loginShell: /bin/sh

MSG
# >>

group_member = "member: cn=%{groupname},ou=Group,dc=redmine,dc=org\n"
user_member = "member: uid=%{username},ou=Person,dc=redmine,dc=org\n"

group = <<MSG
dn: cn=%{groupname},ou=Group,dc=redmine,dc=org
objectClass: groupOfNames
objectClass: posixAccount
homeDirectory: /nonexistent
gidNumber: %{gidNumber}
uidNumber: %{gidNumber}
uid: %{groupname}
cn: %{groupname}
%{members}

MSG
# >>

groups = %w(
  Sayeldas	Iardum	Bluil	Anbely	Issekin	Briklor	Enden
  Rynever	Worathest	Therss	Meyl	Oany	Whod	Tiaris
  Belecer	Rill	Strycheser	Ustuq	Issk	Hatosentan	Llant
  Ghaoll	Kimshy	Irenth	Swien	Endash	Denardon	Hatcer
  Aughny	Kibyno	Tonage	Serende	Bietroth	Engech	Aseta
  Tanusk	Umf	Danasho	Rakm	Honeld	Maedtas	Skelmos
  Sulgard	Tonid	Leris	Rothit	Awkin	Sand	Delusk
  Warad	Dihen	Otiao	Therkal	Wage	Emum	Veaw
  Inequa	Lyeack	Agecerat	Achkim	Enrak	Gulut	Oveso
  Toniv	Kalq	Tiaorm	Calltia	Ascerem	Kaltia	Seraufst
  Honibi	Quadeny	Ridasi	Tegh	Teguno	Sewarhat	Poltiaeld
  Polhini	Liwaren	Atler	Tinenhin	Quever	Tanhtor	Nysos
  Brint	Ageaughtor	Lleef	Yiew	Arbche	Perusul	Ghash
  Etum	Itxash	Lamur	Richit	Smuaddan	Fyzin	Endeves
  Iuski	Tinrothu	Lododu	Iuste	Dimyn	Podynen	Lopisy
  Untros	Igara	Emique	Ruperash	Awend	Slyaugh	Ackrandel
  Ustech	Anarr	Ightwor	Aleing	Nyrak	Cheash	Itora
)

users = %w( loadgeek
tweetmicro
systemhack
tweetsave
microunit
browserclient
webfiber
cabledrive
graphicsfiber
drivechip
iconfiber
corescript
opticipod
blogarray
processipod
waremicro
digiprocess
digiware
iconoptic
scripttweet
clickturtle
ringshark
popsnake
clickowl
tockgiraffe
itchgiraffe
itchdonkey
clickworm
blowgorilla
scratcheagle
yellowcruel
rubycalm
golldhorror
rubyhopeless
blackhappy
whitecross
limegrumpy
lilacgrim
mauvecrrazy
rosemap
leetbroccoli
banana
carrot
winnuts
lolchips
wthfrogs
lmaococonut
winpie
lmaobanana
failcoconut )

names = ['Christian Earheart',
'Rae Croll',
'Darryl Ditto',
'Nelson Meriwether',
'Elnora Gershon',
'Odessa Stingley',
'Kelly Cafferty',
'Dona Austria',
'Ericka Strohl',
'Lakisha Kouba',
'Fernando Dymond',
'Amie Rodreguez',
'Tyrone Winders',
'Rae Degner',
'Darren Canez',
'Earnestine Zahm',
'Fernando Stemm',
'Tanisha Sprowl',
'Saundra Nokes',
'Darren Czerwinski',
'Lenore Messersmith',
'Ashlee Stolz',
'Darryl Schaner',
'Sofia Lacayo',
'Sofia Wiers',
'Lonnie Mccarville',
'Allie Bavaro',
'Sharron Conine',
'Guy Ledger',
'Carmella Kleffman',
'Clayton Rodrick',
'Kathrine Solley',
'Annabelle Riser',
'Julio Wurster',
'Earnestine Camille',
'Hugh Juarbe',
'Guy Hodgin',
'Jamie Alpers',
'Benita Mccrimmon',
'Earnestine Guidroz',
'Ted Formica',
'Jamie Auton',
'Guy Gagnier',
'Tanisha Dahlen',
'Annabelle Spillane',
'Noemi Mcalexander',
'Allan Hynd',
'Fernando Schaner',
'Erik Haubert',
'Jeanie Mazzarella'
]

languages = %w( ar ca de en eu fr hr it lt mn pl ro sl sr-YU tr zh-TWbg cs el es fa gl hu ja lv nl pt-BR ru sq sv uk zhbs da en-GB et fi he id ko mk no pt sk sr th vi )

users = users[0...5]
names = names[0...5]
groups = groups[0...10]

n = 300
users.zip(names).each do |username, fullname|
  puts user.
      gsub('%{username}', username).
      gsub('%{cn}', fullname).
      gsub('%{givenName}', fullname.split(' ')[0]).
      gsub('%{sn}', fullname.split(' ')[1]).
      gsub('%{mail}', "#{username}@fakemail.com").
      gsub('%{uidNumber}', (n += 1).to_s ).
      gsub('%{homeDir}', username).
      gsub('%{language}', languages.sample(:random => rng))
end

n = 4000
groups.each do |groupname|
  members = ""
  selected_users = []
  selected_groups = []
  (1..(1+rng.rand(3))).each do |i|
    if rng.rand(2) == 0
      name = (users - selected_users).sample(:random => rng)
      members += user_member.gsub('%{username}', name)
      selected_users << name
    else
      name = (groups - selected_groups).sample(:random => rng)
      members += group_member.gsub('%{groupname}', name)
      selected_groups << name
    end
  end
  puts group.
        gsub('%{groupname}', groupname).
	gsub('%{gidNumber}', (n += 1).to_s ).
        gsub('%{members}', members)
end
