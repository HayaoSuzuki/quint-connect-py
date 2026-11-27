use std::collections::BTreeMap;

pub(super) type NodeId = usize;
pub(super) enum Node {
    Bool(bool),
    Text(String),
    Number,
    Null,
    Array(Vec<NodeId>),
    Object(BTreeMap<String, NodeId>),
}

pub(super) enum ParseError {
    Syntax,
    Duplicate,
}

pub(super) struct Document {
    pub(super) nodes: Vec<Node>,
    pub(super) root: NodeId,
}

impl Document {
    pub(super) fn parse(text: &str) -> Result<Self, ParseError> {
        let mut parser = Parser {
            bytes: text.as_bytes(),
            offset: 0,
            nodes: Vec::new(),
            duplicate: false,
        };
        let root = parser.document().ok_or(ParseError::Syntax)?;
        if parser.duplicate {
            return Err(ParseError::Duplicate);
        }
        Ok(Self {
            nodes: parser.nodes,
            root,
        })
    }

    pub(super) fn object(&self, id: NodeId) -> Option<&BTreeMap<String, NodeId>> {
        match &self.nodes[id] {
            Node::Object(fields) => Some(fields),
            _ => None,
        }
    }

    pub(super) fn array(&self, id: NodeId) -> Option<&[NodeId]> {
        match &self.nodes[id] {
            Node::Array(items) => Some(items),
            _ => None,
        }
    }

    pub(super) fn text(&self, id: NodeId) -> Option<&str> {
        match &self.nodes[id] {
            Node::Text(text) => Some(text),
            _ => None,
        }
    }
}

// Container nesting is kept off the Rust stack. Number tokens are checked
// lexically so discarded metadata cannot impose a floating-point range limit.
enum Container {
    Array(Vec<NodeId>),
    Object(BTreeMap<String, NodeId>, String),
}

struct Parser<'a> {
    bytes: &'a [u8],
    offset: usize,
    nodes: Vec<Node>,
    duplicate: bool,
}

impl Parser<'_> {
    fn document(&mut self) -> Option<NodeId> {
        let mut stack = Vec::new();
        loop {
            self.whitespace();
            let node = match self.peek()? {
                b'[' => {
                    self.offset += 1;
                    if self.consume(b']') {
                        Node::Array(Vec::new())
                    } else {
                        stack.push(Container::Array(Vec::new()));
                        continue;
                    }
                }
                b'{' => {
                    self.offset += 1;
                    if self.consume(b'}') {
                        Node::Object(BTreeMap::new())
                    } else {
                        stack.push(Container::Object(BTreeMap::new(), self.key()?));
                        continue;
                    }
                }
                b'"' => Node::Text(self.string()?),
                b't' => {
                    self.literal(b"true")?;
                    Node::Bool(true)
                }
                b'f' => {
                    self.literal(b"false")?;
                    Node::Bool(false)
                }
                b'n' => {
                    self.literal(b"null")?;
                    Node::Null
                }
                b'-' | b'0'..=b'9' => {
                    self.number()?;
                    Node::Number
                }
                _ => return None,
            };
            let mut id = self.push(node);
            while let Some(container) = stack.pop() {
                let parent = match container {
                    Container::Array(mut items) => {
                        items.push(id);
                        if self.consume(b',') {
                            stack.push(Container::Array(items));
                            break;
                        }
                        self.consume(b']').then_some(Node::Array(items))?
                    }
                    Container::Object(mut fields, key) => {
                        self.duplicate |= fields.insert(key, id).is_some();
                        if self.consume(b',') {
                            stack.push(Container::Object(fields, self.key()?));
                            break;
                        }
                        self.consume(b'}').then_some(Node::Object(fields))?
                    }
                };
                id = self.push(parent);
            }
            if stack.is_empty() {
                self.whitespace();
                return (self.offset == self.bytes.len()).then_some(id);
            }
        }
    }

    fn key(&mut self) -> Option<String> {
        self.whitespace();
        let key = self.string()?;
        self.consume(b':').then_some(key)
    }

    fn push(&mut self, node: Node) -> NodeId {
        let id = self.nodes.len();
        self.nodes.push(node);
        id
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.offset).copied()
    }

    fn whitespace(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t' | b'\r' | b'\n')) {
            self.offset += 1;
        }
    }

    fn consume(&mut self, byte: u8) -> bool {
        self.whitespace();
        if self.peek() != Some(byte) {
            return false;
        }
        self.offset += 1;
        true
    }

    fn literal(&mut self, literal: &[u8]) -> Option<()> {
        if !self.bytes[self.offset..].starts_with(literal) {
            return None;
        }
        self.offset += literal.len();
        Some(())
    }

    fn string(&mut self) -> Option<String> {
        let start = self.offset;
        if self.peek()? != b'"' {
            return None;
        }
        self.offset += 1;
        loop {
            match self.peek()? {
                b'\\' => self.offset += 2,
                b'"' => {
                    self.offset += 1;
                    return serde_json::from_slice(&self.bytes[start..self.offset]).ok();
                }
                _ => self.offset += 1,
            }
        }
    }

    fn number(&mut self) -> Option<()> {
        if self.peek()? == b'-' {
            self.offset += 1;
        }
        match self.peek()? {
            b'0' => self.offset += 1,
            b'1'..=b'9' => self.digits()?,
            _ => return None,
        }
        if self.peek() == Some(b'.') {
            self.offset += 1;
            self.digits()?;
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.offset += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.offset += 1;
            }
            self.digits()?;
        }
        Some(())
    }

    fn digits(&mut self) -> Option<()> {
        let start = self.offset;
        while matches!(self.peek(), Some(b'0'..=b'9')) {
            self.offset += 1;
        }
        (start < self.offset).then_some(())
    }
}
