import Foundation

public enum EvidenceClaimRegistry {
    public static let version = 2
    public static let claims: [EvidenceClaim] = [
        EvidenceClaim((
            id: "continuous-stable-capture",
            sourceURL: "https://cpb-us-e2.wpmucdn.com/faculty.sites.uci.edu/dist/2/425/files/2011/03/video-research-guidelines.pdf",
            construct: "Kontinuierliche, überprüfbare Videoaufzeichnung",
            requiredObservable: "Lokaler Aufnahmezustand, Kameraruhe und Belichtung",
            allowedWordingDE: "Die App meldet direkte Aufnahmebedingungen; deren wissenschaftliche Eignung muss das jeweilige Forschungsprotokoll bestimmen.",
            prohibitedWordingDE: [
                "forschungstaug",
                "forschungsgeeignet",
                "wissenschaftlich bereit",
                "analysegeeignet"
            ],
            validationTier: .documented
        )),
        EvidenceClaim((
            id: "direct-visual-observability",
            sourceURL: "https://cpb-us-e2.wpmucdn.com/faculty.sites.uci.edu/dist/2/425/files/2011/03/video-research-guidelines.pdf",
            construct: "Direkt beobachtbare Bild- und Gerätesignale",
            requiredObservable: "Gerätelage, Bewegung, Belichtung und algorithmisch verfügbare Bildstruktur",
            allowedWordingDE: "Die App beschreibt direkte Bild- und Gerätesignale und enthält sich bei fehlender Messung; sie bewertet keine Unterrichtsqualität.",
            prohibitedWordingDE: [
                "unterrichtsqualität erkannt",
                "pädagogisch qualität erkannt",
                "aufmerksamkeit erkannt",
                "engagement erkannt",
                "kognitiv aktivierung erkannt",
                "feedbackqualität erkannt"
            ],
            validationTier: .unitTested
        )),
        EvidenceClaim((
            id: "audio-amplitude-boundary",
            sourceURL: "https://www.itu.int/rec/R-REC-BS.1770/en",
            construct: "Normalisierte Audioamplitude und Nähe zur digitalen Vollaussteuerung",
            requiredObservable: "Normalisierte Spitzen- und mittlere Spitzenamplitude pro Frame des lokalen Eingangssignals",
            allowedWordingDE: "Der lokale Pegeltest beschreibt Signalstärke und die Nähe zur digitalen Vollaussteuerung; er misst weder True Peak noch Sprachverständlichkeit oder Aussetzerfreiheit.",
            prohibitedWordingDE: [
                "clipping erkannt",
                "clipfrei",
                "dropoutfrei",
                "aussetzer erkannt",
                "audio aufnahmebereit",
                "guter arbeitsbereich"
            ],
            validationTier: .unitTested
        )),
        EvidenceClaim((
            id: "speech-intelligibility-boundary",
            sourceURL: "https://webstore.iec.ch/en/publication/26771",
            construct: "Sprachverständlichkeit als eigenständiges Messkonstrukt",
            requiredObservable: "Ein dafür validiertes Verständlichkeitsmaß, das die App derzeit nicht erhebt",
            allowedWordingDE: "Audioamplitude ist kein Nachweis der Sprachverständlichkeit; diese wird von der App nicht gemessen.",
            prohibitedWordingDE: [
                "sprachverständlich",
                "sprachverständlichkeit geprüft",
                "sprache verständlich erkannt"
            ],
            validationTier: .documented
        )),
        EvidenceClaim((
            id: "local-consent-record",
            sourceURL: "https://cpb-us-e2.wpmucdn.com/faculty.sites.uci.edu/dist/2/425/files/2011/03/video-research-guidelines.pdf",
            construct: "Lokale Dokumentation von Einwilligungsbestätigungen und Widerruf",
            requiredObservable: "Vom lokalen Nutzer bestätigte Geltungsbereiche, Zeitpunkte und Widerrufsstatus",
            allowedWordingDE: "Die App speichert lokale Bestätigungen und Widerrufe; sie prüft weder die rechtliche Wirksamkeit noch die Identität oder tatsächliche Information aller Beteiligten.",
            prohibitedWordingDE: [
                "gültig einwillig",
                "rechtssicher",
                "aufnahme freigegeben",
                "datenschutzkonform",
                "einwilligung geprüft"
            ],
            validationTier: .unitTested
        )),
        EvidenceClaim((
            id: "adapted-laf-reflection",
            sourceURL: "https://doi.org/10.1007/s11858-010-0292-3",
            construct: "An Santagatas Lesson Analysis Framework angelehnte Reflexionsfragen",
            requiredObservable: "Vom Nutzer eingegebene Ziele, Lernbelege, Strategien und Alternativen",
            allowedWordingDE: "Die vier Reflexionsfelder sind an das Lesson Analysis Framework angelehnt; die App implementiert ein lokales Gerüst, nicht das validierte Originalinstrument.",
            prohibitedWordingDE: [
                "laf validiert",
                "validiert reflexion",
                "wirksam reflexion",
                "lernwirksamkeit nachgewiesen"
            ],
            validationTier: .unitTested
        )),
        EvidenceClaim((
            id: "experimental-observation-hypotheses",
            sourceURL: "https://www.oecd.org/en/about/projects/global-teaching-insights.html",
            construct: "Experimentelle IPN-, TIMSS- und GTI-inspirierte Regelhypothesen",
            requiredObservable: "Explizit aktivierter Forschungsmodus, Protokollreferenz und regelbasierte Aktivierung",
            allowedWordingDE: "Die Ausgabe enthält unvalidierte Regelhypothesen; Regelunterstützung ist weder Wahrscheinlichkeit noch menschliche oder psychometrisch validierte Kodierung.",
            prohibitedWordingDE: [
                "validiert kodier",
                "psychometrisch validier",
                "international vergleich",
                "raterübergreifend zuverlässig",
                "gti konform",
                "timss konform",
                "ipn konform",
                "code wahrscheinlich"
            ],
            validationTier: .unitTested
        )),
        EvidenceClaim((
            id: "human-coding-reliability-boundary",
            sourceURL: "https://nces.ed.gov/pubs99/1999074.pdf",
            construct: "Trainierte menschliche Kodierung und Interrater-Reliabilität",
            requiredObservable: "Kodierertraining, unabhängige Mehrfachkodierung und berichtete Reliabilitätsstatistik",
            allowedWordingDE: "Die App führt keine menschliche Mehrfachkodierung oder Reliabilitätsprüfung durch und beansprucht daher keine Vergleichbarkeit mit TIMSS-Videokodierungen.",
            prohibitedWordingDE: [
                "interrater reliabel",
                "kodierer reliabel",
                "timss vergleichbar",
                "international vergleich"
            ],
            validationTier: .documented
        ))
    ]

}
