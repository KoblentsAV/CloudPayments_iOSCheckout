import UIKit
import Alamofire
import AFNetworking

enum PayType {
    case charge
    case auth
    
    var description: String {
        switch self {
        case .charge:
            return .oneStagePayment
        case .auth:
            return .twoStagePayment
        }
    }
}

final class CheckoutViewController: UIViewController {
    
    private var payType: PayType!
    
    private let network = NetworkService()
    
    // MARK: - Outlets
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var loadingIndicator: UIActivityIndicatorView!
    @IBOutlet weak var textFieldCardNumber: UITextField!
    @IBOutlet weak var textFieldExpDate: UITextField!
    @IBOutlet weak var textFieldHolderName: UITextField!
    @IBOutlet weak var textFieldCVV: UITextField!
    @IBOutlet weak var buttonApplePay: UIButton!
    
    let SupportedPaymentNetworks = [PKPaymentNetwork.visa, PKPaymentNetwork.masterCard] // Платежные системы для Apple Pay
    let ApplePayMerchantID = "merchant.com.YOURDOMAIN" // Ваш ID для Apple Pay!
    
    /// Instantiate `CheckoutViewController` from storyboard
    static func storyboardInstance(payType: PayType) -> CheckoutViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: String(describing: self)) as! CheckoutViewController
        vc.payType = payType
        return vc
    }
    
    // MARK: - View life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.hideKeyboardWhenTappedAround()
        
        textFieldCardNumber.delegate = self
        textFieldExpDate.delegate = self
        
        self.loadingIndicator.isHidden = true
        title = payType.description
        
        buttonApplePay.isHidden = !PKPaymentAuthorizationViewController.canMakePayments(usingNetworks: SupportedPaymentNetworks) // Проверяем возможно ли использовать Apple Pay
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notifications callbacks
    
    @objc func keyboardWillShow(notification: NSNotification) {
        var userInfo = notification.userInfo!
        var keyboardFrame = (userInfo[UIKeyboardFrameBeginUserInfoKey] as! NSValue).cgRectValue
        keyboardFrame = self.view.convert(keyboardFrame, from: nil)
        
        var contentInset = self.scrollView.contentInset
        contentInset.bottom = keyboardFrame.size.height
        scrollView.contentInset = contentInset
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        let contentInset = UIEdgeInsets.zero
        scrollView.contentInset = contentInset
    }
    
    @IBAction func onPayClick(_ sender: Any) {
        
        // Получаем введенные данные банковской карты
        guard let cardNumber = textFieldCardNumber.text, !cardNumber.isEmpty else {
            self.showAlert(title: .errorWord, message: .enterCardNumber)
            return
        }
        
        if !Card.isCardNumberValid(cardNumber) {
            self.showAlert(title: .errorWord, message: .enterCorrectCardNumber)
            return
        }
        
        guard let expDate = textFieldExpDate.text, expDate.count == 5 else {
            self.showAlert(title: .errorWord, message: .enterExpirationDate)
            return
        }
        
        guard let holderName = textFieldHolderName.text, !holderName.isEmpty else {
            self.showAlert(title: .errorWord, message: .enterCardHolder)
            return
        }
        
        guard let cvv = textFieldCVV.text, !cvv.isEmpty else {
            self.showAlert(title: .errorWord, message: .enterCVVCode)
            return
        }
        
        // Создаем объект Card
        let card = Card()
        
        // Создаем криптограмму карточных данных
        // Чтобы создать криптограмму необходим PublicID (свой PublicID можно посмотреть в личном кабинете и затем заменить в файле Constants)
        let cardCryptogramPacket = card.makeCryptogramPacket(cardNumber, andExpDate: expDate, andCVV: cvv, andMerchantPublicID: Constants.merchantPulicId)
        
        guard let packet = cardCryptogramPacket else {
            self.showAlert(title: .errorWord, message: .errorCreatingCryptoPacket)
            return
        }
        
        // Используя методы API выполняем оплату по криптограмме
        // (charge (для одностадийного платежа) или auth (для двухстадийного))
        switch payType {
        case .charge?:
            charge(cardCryptogramPacket: packet, cardHolderName: holderName)
        case .auth?:
            auth(cardCryptogramPacket: packet, cardHolderName: holderName)
        default:
            return
        }
    }
    
    @IBAction func onApplePayClick(_ sender: Any) {
        
        // Формируем запрос для Apple Pay
        let request = PKPaymentRequest()
        request.merchantIdentifier = ApplePayMerchantID
        request.supportedNetworks = SupportedPaymentNetworks
        request.merchantCapabilities = PKMerchantCapability.capability3DS // Возможно использование 3DS
        request.countryCode = "RU" // Код страны
        request.currencyCode = "RUB" // Код валюты
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "Рубль", amount: 1) // Информация о товаре (название и цена)
        ]
        let applePayController = PKPaymentAuthorizationViewController(paymentRequest: request)
        applePayController?.delegate = self
        self.present(applePayController!, animated: true, completion: nil)
    }
}

// Обработка результата для Apple Pay
// ВНИМАНИЕ! Нельзя тестировать Apple Pay в симуляторе, так как в симуляторе payment.token.paymentData всегда nil
extension CheckoutViewController: PKPaymentAuthorizationViewControllerDelegate {
    func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, completion: @escaping ((PKPaymentAuthorizationStatus) -> Void)) {
        completion(PKPaymentAuthorizationStatus.success)
        
        // Конвертируем объект PKPayment в строку криптограммы
        guard let cryptogram = PKPaymentConverter.convert(toString: payment) else {
            return
        }
        
        print(cryptogram)
        
        // Используя методы API выполняем оплату по криптограмме
        // (charge (для одностадийного платежа) или auth (для двухстадийного))
        switch payType {
        case .charge?:
            charge(cardCryptogramPacket: cryptogram, cardHolderName: "")
        case .auth?:
            auth(cardCryptogramPacket: cryptogram, cardHolderName: "")
        default:
            return
        }
    }
    
    func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
}

extension CheckoutViewController: UIWebViewDelegate {
    
    /// Handle result from 3DS form
    func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType) -> Bool {
        let urlString = request.url?.absoluteString
        if (urlString == Constants.cloudpaymentsURL) {
            var response: String? = nil
            if let aBody = request.httpBody {
                response = String(data: aBody, encoding: .ascii)
            }
            let responseDictionary = parse(response: response)
            webView.removeFromSuperview()
            post3ds(transactionId: responseDictionary?["MD"] as! String, paRes: responseDictionary?["PaRes"] as! String)
            return false
        }
        return true
    }
}

extension CheckoutViewController: UITextFieldDelegate {
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        switch textField {
            // Пример определения типа платежной системы по номеру карты:
        // Определяем тип во время ввода номера карты и выводим данные в лог
        case textFieldCardNumber:
            print(Card.cardType(toString: Card.cardType(fromCardNumber: textField.text)))
            return true
        case textFieldExpDate:
            // original answer https://stackoverflow.com/a/47077265
            if range.length > 0 {
                return true
            }
            if string == "" {
                return false
            }
            if range.location > 4 {
                return false
            }
            var originalText = textField.text
            let replacementText = string.replacingOccurrences(of: " ", with: "")
            
            // Verify entered text is a numeric value
            if !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: replacementText)) {
                return false
            }
            
            // Put / after 2 digit
            if range.location == 2 {
                originalText?.append("/")
                textField.text = originalText
            }
            return true
            
        default:
            return true
        }
    }
}

// MARK: - Private methods
private extension CheckoutViewController {
    
    // Это тестовое приложение и запросы выполняются на прямую на сервер CloudPayment
    // Не храните пароль для API в приложении!
    // Правильно выполнять запросы по этой схеме:
    // 1) В приложении необходимо получить данные карты: номер, срок действия, имя держателя и CVV.
    // 2) Создать криптограмму карточных данных при помощи SDK.
    // 3) Отправить криптограмму и все данные для платежа с мобильного устройства на ваш сервер.
    // 4) С сервера выполнить оплату через платежное API CloudPayments.
    func charge(cardCryptogramPacket: String, cardHolderName: String) {
        
        self.showLoadingIndicator()
        
        network.charge(cardCryptogramPacket: cardCryptogramPacket, cardHolderName: cardHolderName) { [weak self] result in
            
            self?.hideLoadingIndicator()
            
            switch result {
            case .success(let transactionResponse):
                print("success")
                self?.checkTransactionResponse(transactionResponse: transactionResponse)
            case .failure(let error):
                print("error")
                self?.showAlert(title: .errorWord, message: error.localizedDescription)
            }
        }
    }
    
    // Это тестовое приложение и запросы выполняются на прямую на сервер CloudPayment
    // Не храните пароль для API в приложении!
    // Правильно выполнять запросы по этой схеме:
    // 1) В приложении необходимо получить данные карты: номер, срок действия, имя держателя и CVV.
    // 2) Создать криптограмму карточных данных при помощи SDK.
    // 3) Отправить криптограмму и все данные для платежа с мобильного устройства на ваш сервер.
    // 4) С сервера выполнить оплату через платежное API CloudPayments.
    func auth(cardCryptogramPacket: String, cardHolderName: String) {
        
        self.showLoadingIndicator()
        
        network.auth(cardCryptogramPacket: cardCryptogramPacket, cardHolderName: cardHolderName) { [weak self] result in
            
            self?.hideLoadingIndicator()
            
            switch result {
            case .success(let transactionResponse):
                print("success")
                self?.checkTransactionResponse(transactionResponse: transactionResponse)
            case .failure(let error):
                print("error")
                self?.showAlert(title: .errorWord, message: error.localizedDescription)
            }
        }
    }
    
    // Проверяем необходимо ли подтверждение с использованием 3DS
    func checkTransactionResponse(transactionResponse: TransactionResponse) {
        if (transactionResponse.success) {
            
            // Показываем результат
            self.showAlert(title: .informationWord, message: transactionResponse.transaction?.cardHolderMessage)
        } else {
            
            if (!transactionResponse.message.isEmpty) {
                self.showAlert(title: .errorWord, message: transactionResponse.message)
                return
            }
            if (transactionResponse.transaction?.paReq != nil && transactionResponse.transaction?.acsUrl != nil) {
                
                let transactionId = String(describing: transactionResponse.transaction?.transactionId ?? 0)
                
                // Показываем 3DS форму
                D3DS.make3DSPayment(with: self, andAcsURLString: transactionResponse.transaction?.acsUrl, andPaReqString: transactionResponse.transaction?.paReq, andTransactionIdString: transactionId)
            } else {
                self.showAlert(title: .informationWord, message: transactionResponse.transaction?.cardHolderMessage)
            }
        }
    }
    
    func post3ds(transactionId: String, paRes: String) {
        
        self.showLoadingIndicator()
        
        network.post3ds(transactionId: transactionId, paRes: paRes) { [weak self] result in
            
            self?.hideLoadingIndicator()
            
            switch result {
            case .success(let transactionResponse):
                print("success")
                self?.checkTransactionResponse(transactionResponse: transactionResponse)
            case .failure(let error):
                print("error")
                self?.showAlert(title: .errorWord, message: error.localizedDescription)
            }
        }
    }
    
    func showLoadingIndicator() {
        self.loadingIndicator.isHidden = false
        self.loadingIndicator.startAnimating()
    }
    
    func hideLoadingIndicator() {
        self.loadingIndicator.stopAnimating()
        self.loadingIndicator.isHidden = true
    }
    
    // MARK: - Utilities
    
    func parse(response: String?) -> [AnyHashable: Any]? {
        guard let response = response else {
            return nil
        }
        
        let pairs = response.components(separatedBy: "&")
        let elements = pairs.map { $0.components(separatedBy: "=") }
        let dict = elements.reduce(into: [String: String]()) {
            $0[$1[0].removingPercentEncoding!] = $1[1].removingPercentEncoding
        }
        
        return dict
    }
}


