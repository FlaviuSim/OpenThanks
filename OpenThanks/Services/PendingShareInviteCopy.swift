import Foundation
import NaturalLanguage

/// Invite / share wrapper copy matched to the appreciation message language.
enum PendingShareInviteCopy {
    enum Language: String, Equatable {
        case english = "en"
        case spanish = "es"
        case french = "fr"
        case german = "de"
        case portuguese = "pt"
        case italian = "it"
        case romanian = "ro"
        case dutch = "nl"

        static func detect(from message: String) -> Language {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 12 else { return .english }

            let recognizer = NLLanguageRecognizer()
            recognizer.processString(trimmed)
            guard let code = recognizer.dominantLanguage?.rawValue.lowercased() else {
                return .english
            }
            let base = String(code.prefix(2))
            switch base {
            case "es": return .spanish
            case "fr": return .french
            case "de": return .german
            case "pt": return .portuguese
            case "it": return .italian
            case "ro": return .romanian
            case "nl": return .dutch
            default: return .english
            }
        }
    }

    /// Short mailto subject — body carries the invite + link.
    static func emailSubject(isPrivate: Bool, language: Language) -> String {
        switch language {
        case .english:
            return isPrivate
                ? "A private appreciation for you"
                : "An appreciation for you"
        case .spanish:
            return isPrivate
                ? "Un agradecimiento privado para ti"
                : "Un agradecimiento para ti"
        case .french:
            return isPrivate
                ? "Une appréciation privée pour toi"
                : "Une appréciation pour toi"
        case .german:
            return isPrivate
                ? "Eine private Wertschätzung für dich"
                : "Eine Wertschätzung für dich"
        case .portuguese:
            return isPrivate
                ? "Uma apreciação privada para você"
                : "Uma apreciação para você"
        case .italian:
            return isPrivate
                ? "Un apprezzamento privato per te"
                : "Un apprezzamento per te"
        case .romanian:
            return isPrivate
                ? "O apreciere privată pentru tine"
                : "O apreciere pentru tine"
        case .dutch:
            return isPrivate
                ? "Een privé waardering voor jou"
                : "Een waardering voor jou"
        }
    }

    static func inviteCaption(
        firstName: String?,
        preview: String?,
        isPrivate: Bool,
        language: Language
    ) -> String {
        let name = firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasName = !(name?.isEmpty ?? true)
        let previewBit: String = {
            guard let preview, !preview.isEmpty else { return "" }
            return previewClause(preview, language: language)
        }()

        switch language {
        case .english:
            let greeting = hasName ? "Hey \(name!)! " : "Hey! "
            let kind = isPrivate ? "a private appreciation" : "an appreciation"
            return greeting
                + "I wrote you \(kind) on OpenThanks 💛\(previewBit) You can read and accept it here:"
        case .spanish:
            let greeting = hasName ? "¡Hola \(name!)! " : "¡Hola! "
            let kind = isPrivate ? "un agradecimiento privado" : "un agradecimiento"
            return greeting
                + "Te escribí \(kind) en OpenThanks 💛\(previewBit) Puedes leerlo y aceptarlo aquí:"
        case .french:
            let greeting = hasName ? "Salut \(name!) ! " : "Salut ! "
            let kind = isPrivate ? "une appréciation privée" : "une appréciation"
            return greeting
                + "Je t’ai écrit \(kind) sur OpenThanks 💛\(previewBit) Tu peux la lire et l’accepter ici :"
        case .german:
            let greeting = hasName ? "Hey \(name!)! " : "Hey! "
            let kind = isPrivate ? "eine private Wertschätzung" : "eine Wertschätzung"
            return greeting
                + "Ich habe dir \(kind) auf OpenThanks geschrieben 💛\(previewBit) Du kannst sie hier lesen und annehmen:"
        case .portuguese:
            let greeting = hasName ? "Oi \(name!)! " : "Oi! "
            let kind = isPrivate ? "uma apreciação privada" : "uma apreciação"
            return greeting
                + "Escrevi \(kind) para você no OpenThanks 💛\(previewBit) Você pode ler e aceitar aqui:"
        case .italian:
            let greeting = hasName ? "Ciao \(name!)! " : "Ciao! "
            let kind = isPrivate ? "un apprezzamento privato" : "un apprezzamento"
            return greeting
                + "Ti ho scritto \(kind) su OpenThanks 💛\(previewBit) Puoi leggerlo e accettarlo qui:"
        case .romanian:
            let greeting = hasName ? "Salut \(name!)! " : "Salut! "
            let kind = isPrivate ? "o apreciere privată" : "o apreciere"
            return greeting
                + "Ți-am scris \(kind) pe OpenThanks 💛\(previewBit) Poți citi și accepta aici:"
        case .dutch:
            let greeting = hasName ? "Hoi \(name!)! " : "Hoi! "
            let kind = isPrivate ? "een privé waardering" : "een waardering"
            return greeting
                + "Ik schreef je \(kind) op OpenThanks 💛\(previewBit) Je kunt het hier lezen en accepteren:"
        }
    }

    /// Accepted-appreciation social share lead-in / closer by message language.
    static func socialLeadIn(
        voice: AppreciationShareVoice,
        authorName: String,
        recipientName: String,
        language: Language
    ) -> String {
        switch (language, voice) {
        case (.english, .author):
            return "I'm so grateful for \(recipientName)"
        case (.english, .recipient):
            return "So kind of \(authorName) to send me a gratitude on OpenThanks"
        case (.english, .viewer):
            return "\(authorName) thanked \(recipientName) on OpenThanks:"
        case (.spanish, .author):
            return "Estoy muy agradecido/a por \(recipientName)"
        case (.spanish, .recipient):
            return "Qué amable de \(authorName) enviarme un agradecimiento en OpenThanks"
        case (.spanish, .viewer):
            return "\(authorName) agradeció a \(recipientName) en OpenThanks:"
        case (.french, .author):
            return "Je suis tellement reconnaissant·e envers \(recipientName)"
        case (.french, .recipient):
            return "C’est si gentil de \(authorName) de m’avoir envoyé une gratitude sur OpenThanks"
        case (.french, .viewer):
            return "\(authorName) a remercié \(recipientName) sur OpenThanks :"
        case (.german, .author):
            return "Ich bin \(recipientName) so dankbar"
        case (.german, .recipient):
            return "So nett von \(authorName), mir auf OpenThanks zu danken"
        case (.german, .viewer):
            return "\(authorName) hat \(recipientName) auf OpenThanks gedankt:"
        case (.portuguese, .author):
            return "Sou muito grato(a) por \(recipientName)"
        case (.portuguese, .recipient):
            return "Que carinho de \(authorName) me enviar uma gratidão no OpenThanks"
        case (.portuguese, .viewer):
            return "\(authorName) agradeceu \(recipientName) no OpenThanks:"
        case (.italian, .author):
            return "Sono così grato/a per \(recipientName)"
        case (.italian, .recipient):
            return "Che gentilezza di \(authorName) inviarmi una gratitudine su OpenThanks"
        case (.italian, .viewer):
            return "\(authorName) ha ringraziato \(recipientName) su OpenThanks:"
        case (.romanian, .author):
            return "Sunt atât de recunoscător/oare pentru \(recipientName)"
        case (.romanian, .recipient):
            return "Ce frumos din partea lui \(authorName) să-mi trimită o apreciere pe OpenThanks"
        case (.romanian, .viewer):
            return "\(authorName) i-a mulțumit lui \(recipientName) pe OpenThanks:"
        case (.dutch, .author):
            return "Ik ben zo dankbaar voor \(recipientName)"
        case (.dutch, .recipient):
            return "Zo lief van \(authorName) om mij een dankbaarheid op OpenThanks te sturen"
        case (.dutch, .viewer):
            return "\(authorName) bedankte \(recipientName) op OpenThanks:"
        }
    }

    static func socialCloser(voice: AppreciationShareVoice, language: Language) -> String {
        switch (language, voice) {
        case (.english, .author):
            return "The full note is on OpenThanks."
        case (.english, .recipient):
            return "Read the full appreciation."
        case (.english, .viewer):
            return "Read it on OpenThanks."
        case (.spanish, .author):
            return "La nota completa está en OpenThanks."
        case (.spanish, .recipient):
            return "Lee el agradecimiento completo."
        case (.spanish, .viewer):
            return "Léelo en OpenThanks."
        case (.french, .author):
            return "Le message complet est sur OpenThanks."
        case (.french, .recipient):
            return "Lis l’appréciation complète."
        case (.french, .viewer):
            return "Lis-la sur OpenThanks."
        case (.german, .author):
            return "Die ganze Notiz ist auf OpenThanks."
        case (.german, .recipient):
            return "Lies die ganze Wertschätzung."
        case (.german, .viewer):
            return "Lies sie auf OpenThanks."
        case (.portuguese, .author):
            return "A nota completa está no OpenThanks."
        case (.portuguese, .recipient):
            return "Leia a apreciação completa."
        case (.portuguese, .viewer):
            return "Leia no OpenThanks."
        case (.italian, .author):
            return "Il messaggio completo è su OpenThanks."
        case (.italian, .recipient):
            return "Leggi l’apprezzamento completo."
        case (.italian, .viewer):
            return "Leggilo su OpenThanks."
        case (.romanian, .author):
            return "Mesajul complet este pe OpenThanks."
        case (.romanian, .recipient):
            return "Citește aprecierea completă."
        case (.romanian, .viewer):
            return "Citește-o pe OpenThanks."
        case (.dutch, .author):
            return "Het volledige bericht staat op OpenThanks."
        case (.dutch, .recipient):
            return "Lees de volledige waardering."
        case (.dutch, .viewer):
            return "Lees het op OpenThanks."
        }
    }

    private static func previewClause(_ preview: String, language: Language) -> String {
        switch language {
        case .english:
            return " It starts: “\(preview)”"
        case .spanish:
            return " Empieza así: “\(preview)”"
        case .french:
            return " Ça commence ainsi : « \(preview) »"
        case .german:
            return " Sie beginnt so: „\(preview)“"
        case .portuguese:
            return " Começa assim: “\(preview)”"
        case .italian:
            return " Inizia così: “\(preview)”"
        case .romanian:
            return " Începe așa: „\(preview)”"
        case .dutch:
            return " Het begint zo: “\(preview)”"
        }
    }
}
