import 'dart:async';
import 'dart:developer';
import 'package:dr_ai/utils/helper/scaffold_snakbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:dr_ai/logic/chat/chat_cubit.dart';
import 'package:dr_ai/data/model/chat_message_model.dart';
import 'package:gap/gap.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; // Add this import
import '../../../logic/validation/formvalidation_cubit.dart';
import '../../widget/chat_bubble.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../utils/constant/color.dart';
import '../../../utils/helper/custom_dialog.dart';
import '../../../utils/helper/extention.dart';
import '../../../utils/constant/image.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _speechEnabled = false;
  String _lastWords = '';
  bool _isSenderLoading = false;
  bool _isReceiverLoading = false;
  bool _isChatDeletingLoading = false;
  bool _isApiInitializing = true;
  bool _isButtonVisible = false;
  List<ChatMessageModel> _chatMessageModel = [];
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  late TextEditingController _txtController;
  late ScrollController _scrollController;
  Timer? _noInputTimer;
  final Duration _noInputDuration = const Duration(seconds: 5);
  
  // Gemini API related properties
  final String _apiKey = 'AIzaSyC0mgALAiYmKS40QXu7dSX9tyEtoj1TY24';
  GenerativeModel? _geminiModel;
  
  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initGeminiModel();
    _getMessages();
    _txtController = TextEditingController();
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      bool isAtBottom = _scrollController.position.pixels <= 100;
      if (!isAtBottom) {
        if (!_isButtonVisible) {
          setState(() {
            _isButtonVisible = true;
          });
        }
      } else {
        if (_isButtonVisible) {
          setState(() {
            _isButtonVisible = false;
          });
        }
      }
    });
  }
  
  // Initialize Gemini model
  Future<void> _initGeminiModel() async {
    try {
      _geminiModel = GenerativeModel(
        model: 'gemini-1.5-flash-latest',
        apiKey: _apiKey,
      );
      log('Gemini model initialized successfully');
    } catch (e) {
      log('Error initializing Gemini model: $e');
      _showApiError('Failed to initialize Gemini model: $e');
    }
  }
  
  // Fixed method to get AI response from Gemini
  Future<String> _getGeminiResponse(String message) async {
    try {
      if (_geminiModel == null) {
        await _initGeminiModel();
        if (_geminiModel == null) {
          return 'Sorry, I am unable to respond right now. Please try again later.';
        }
      }
      
      // Create a content parts array with the user message
      final userMessage = Content.text(message);
      
      // Generate content with the model
      final generationConfig = GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 800,
      );
      
      final response = await _geminiModel!.generateContent([userMessage], 
        generationConfig: generationConfig);
      
      // Get the text from the response
      final responseText = response.text;
      
      if (responseText == null || responseText.isEmpty) {
        return 'I apologize, but I couldn\'t generate a response for your message.';
      }
      
      return responseText;
    } catch (e) {
      log('Error getting Gemini response: $e');
      _showApiError('Failed to get AI response: $e');
      return 'Sorry, an error occurred while processing your request. Please try again.';
    }
  }
  
  void _showApiError(String message) {
    String displayMessage = message;
    
    if (message.contains('API key')) {
      displayMessage = "API key error. Please check your Gemini API key.";
    } else if (message.contains('rate limit')) {
      displayMessage = "Rate limit exceeded. Please try again later.";
    } else if (message.contains('network')) {
      displayMessage = "Network error. Please check your internet connection.";
    }
    
    customSnackBar(context, displayMessage, ColorManager.grey, 3);
  }

  @override
  void dispose() {
    _txtController.dispose();
    _noInputTimer?.cancel();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  Future<void> _startListening() async {
    await _speechToText.listen(
      onResult: _onSpeechResult,
      partialResults: true,
      onSoundLevelChange: null,
      cancelOnError: true,
      localeId: 'ar-EG',
      listenMode: stt.ListenMode.dictation,
    );
    _startNoInputTimer();
    setState(() {});
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    _cancelNoInputTimer();
    setState(() {});
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
      _txtController.text = _lastWords;
      _txtController.selection = TextSelection.fromPosition(
        TextPosition(offset: _txtController.text.length),
      );
    });
    _resetNoInputTimer();
    log(result.recognizedWords);
  }

  void _startNoInputTimer() {
    _noInputTimer = Timer(_noInputDuration, _stopListening);
  }

  void _resetNoInputTimer() {
    _noInputTimer?.cancel();
    _startNoInputTimer();
  }

  void _cancelNoInputTimer() {
    _noInputTimer?.cancel();
  }

  // Modified to use direct Gemini API call
  Future<void> _sendMessage() async {
    String userMessage = _txtController.text.trim();
    if (userMessage.isEmpty) return;
    
    setState(() {
      _isSenderLoading = true;
    });
    
    try {
      // Save user message to Hive via ChatCubit
      context.read<ChatCubit>().sendUserMessage(message: userMessage);
      _txtController.clear();
      
      setState(() {
        _isReceiverLoading = true;
        _isSenderLoading = false;
      });
      
      // Get AI response directly from Gemini
      final aiResponse = await _getGeminiResponse(userMessage);
      
      // Save AI response to Hive via ChatCubit
      context.read<ChatCubit>().saveAiResponse(response: aiResponse);
      
      setState(() {
        _isReceiverLoading = false;
      });
    } catch (e) {
      setState(() {
        _isSenderLoading = false;
        _isReceiverLoading = false;
      });
      log('Error sending message: $e');
      _showApiError(e.toString());
    }
  }

  void onSelected(value) {
    if (value == 'delete') {
      context.read<ChatCubit>().deleteAllMessages();
    }
  }

  void _getMessages() async {
    setState(() {
      _isApiInitializing = true;
    });
    
    try {
      await context.read<ChatCubit>().initHive();
    } catch (e) {
      log('Error initializing Hive: $e');
      _showApiError('Failed to initialize chat history: $e');
    } finally {
      setState(() {
        _isApiInitializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatCubit, ChatState>(
      listener: (context, state) {
        if (state is ChatReceiveSuccess) {
          _chatMessageModel = state.response;
          _scrollToEnd();
        }
        if (state is ChatFailure) {
          _showApiError(state.message);
        }
        if (state is ChatDeletingLoading) {
          _isChatDeletingLoading = true;
        }
        if (state is ChatDeleteSuccess) {
          _isChatDeletingLoading = false;
          customSnackBar(context, "Chat History Deleted Successfully.",
              ColorManager.green, 1);
        }
        if (state is ChatDeleteFailure) {
          _isChatDeletingLoading = false;
          customSnackBar(context, "Failed to delete chat history.",
              ColorManager.grey, 2);
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("Doctor AI Chat"),
            shape: context.appBarTheme.shape,
            actions: [
              _buildPopupMenuButton(),
            ],
          ),
          floatingActionButton:
              _isButtonVisible ? _buildFloatingActionButton() : null,
          bottomNavigationBar: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Padding(
              padding: const EdgeInsets.only(
                  right: 14, left: 14, top: 5, bottom: 10),
              child: _buildChatTextField(context),
            ),
          ),
          body: _isApiInitializing 
              ? _buildApiInitializingIndicator()
              : _chatMessageModel.isEmpty
                  ? _buildEmptyChatBackgroud()
                  : _isChatDeletingLoading
                      ? _buildLoadingIndicator()
                      : _buildMessages(),
        );
      },
    );
  }

  Widget _buildApiInitializingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40.w,
            height: 40.w,
            child: const CircularProgressIndicator(
              strokeCap: StrokeCap.round,
              color: ColorManager.green,
            ),
          ),
          Gap(16.h),
          Text("Initializing Doctor AI...",
              style: context.textTheme.bodyMedium),
          Gap(8.h),
          Text("Powered by Google Gemini",
              style: context.textTheme.bodySmall?.copyWith(
                color: ColorManager.grey,
                fontSize: 12.sp,
              )),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Align(
      alignment: Alignment.center,
      child: Container(
        alignment: Alignment.center,
        width: 50.w,
        height: 50.w,
        decoration: BoxDecoration(
          color: ColorManager.green.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: SizedBox(
          width: 25.w,
          height: 25.w,
          child: const CircularProgressIndicator(
            strokeCap: StrokeCap.round,
            color: ColorManager.white,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChatBackgroud() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            ImageManager.chatIcon,
            width: 100.w,
            height: 100.h,
            // ignore: deprecated_member_use
            color: ColorManager.green,
          ),
          Gap(16.h),
          Text("Start Chatting With Dr. AI",
              style: context.textTheme.bodyMedium),
          Gap(8.h),
          Text("Powered by Google Gemini",
              style: context.textTheme.bodySmall?.copyWith(
                color: ColorManager.grey,
                fontSize: 12.sp,
              )),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      itemCount: _chatMessageModel.length + (_isReceiverLoading ? 1 : 0),
      reverse: true,
      itemBuilder: (context, index) {
        if (_isReceiverLoading && index == 0) {
          return const ChatBubbleForLoading();
        } else {
          final chatIndex = _isReceiverLoading ? index - 1 : index;
          final chatMessage = _chatMessageModel[chatIndex];
          return chatMessage.isUser
              ? ChatBubbleForGuest(message: chatMessage.message)
              : ChatBubbleForDrAi(
                  message: chatMessage.message,
                  time: chatMessage.timeTamp,
                );
        }
      },
    );
  }

  Widget _buildChatTextField(BuildContext context) {
    final cubit = context.bloc<ValidationCubit>();
    return TextField(
      minLines: 1,
      maxLines: 4,
      onChanged: (text) {
        if (text.length == 1) {
          setState(() {});
          log("onChanged");
        }
      },
      style: context.textTheme.bodySmall?.copyWith(color: ColorManager.black),
      cursorColor: ColorManager.green,
      controller: _txtController,
      textDirection: cubit.getFieldDirection(_txtController.text),
      onSubmitted: (_) => _sendMessage(),
      decoration: InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        hintText: 'Write Your Message..',
        suffixIcon: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_speechToText.isNotListening)
              IconButton(
                onPressed: _startListening,
                icon: SvgPicture.asset(ImageManager.recordIcon),
              ),
            if (_speechToText.isListening)
              IconButton(
                onPressed: _stopListening,
                icon: const Icon(Icons.stop, color: Colors.red),
              ),
            IconButton(
              onPressed: (_isReceiverLoading || _isSenderLoading) ? null : () => _sendMessage(),
              icon: Icon(
                Icons.send,
                color: (_isReceiverLoading || _isSenderLoading) 
                    ? ColorManager.grey
                    : ColorManager.green,
                size: 25,
              ),
            ),
          ],
        ),
        enabledBorder: context.inputDecoration.border,
        focusedBorder: context.inputDecoration.border,
      ),
    );
  }

  PopupMenuButton _buildPopupMenuButton() {
    return PopupMenuButton<String>(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
      ),
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      offset: const Offset(0, 40),
      color: ColorManager.white,
      itemBuilder: (BuildContext context) {
        return [
          PopupMenuItem<String>(
            height: 28.h,
            value: 'delete',
            child: Text('Clear Chat History',
                style: context.textTheme.bodySmall
                    ?.copyWith(color: ColorManager.black)),
          ),
        ];
      },
    );
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton.small(
      splashColor: ColorManager.white.withOpacity(0.3),
      elevation: 2,
      onPressed: _scrollToEnd,
      backgroundColor: ColorManager.green,
      child: const Icon(
        Icons.keyboard_double_arrow_down_rounded,
        color: ColorManager.white,
      ),
    );
  }

  void _scrollToEnd() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 700),
        curve: Curves.fastOutSlowIn,
      );
    }
  }
}